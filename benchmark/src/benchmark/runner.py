"""Run one candidate model through the full corpus, N trials each.

Writes one JSONL row per (prompt × trial) to `results/raw/<model_id_safe>.jsonl`.

Production parity:
- Uses `envelope.render_user_envelope` to build a single user message that
  matches `buildGoDeeperUserContent` in go-deeper.ts (lines 521-632).
- Calls OpenRouter with production temperature (1.0), max_completion_tokens
  (1024), reasoning ({effort:minimal, exclude:true}), and provider policy
  ({zdr:true, sort:latency, preferred_max_latency:{p90:3}}).
- Schema validation was removed in v1.1 because Go Deeper does not emit JSON.

Run controls:
- `resume=True` (default) skips (prompt_id, trial) pairs already present in
  the output JSONL — safe to Ctrl+C and re-run.
- `max_cost_usd` aborts cleanly once the running total reaches the cap.
- `dry_run=True` prints an estimated cost and returns without making API calls.
- A status line is appended to `<out_path>.status.log` after every call so
  another terminal can `tail -f` the file and see live progress.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from rich.console import Console
from rich.progress import Progress

from .client import (
    OpenRouterClient,
    PRODUCTION_PROVIDER_POLICY,
    PRODUCTION_REASONING_POLICY,
)
from .envelope import render_user_envelope
from .pricing import ModelPricing, cost_usd
from .schema import (
    BenchmarkResult,
    LatencyMetrics,
    TokenUsage,
)


console = Console()

# Production-observed token average from the user's OpenRouter dashboard
# (May 2026), used for dry-run cost estimation.
EST_INPUT_TOKENS = 3650
EST_OUTPUT_TOKENS = 1200


def safe_filename(model_id: str) -> str:
    return re.sub(r"[^a-zA-Z0-9._-]", "_", model_id)


def build_messages(
    system_prompt: str,
    prompt_turns: list[dict[str, str]],
) -> list[dict[str, str]]:
    """Build the production-shaped [system, user] message pair."""
    user_content = render_user_envelope(turns=prompt_turns)
    return [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_content},
    ]


def _load_already_done(out_path: Path) -> set[tuple[str, int]]:
    """Return the (prompt_id, trial) pairs already in the output JSONL."""
    done: set[tuple[str, int]] = set()
    if not out_path.exists():
        return done
    for line in out_path.read_text().splitlines():
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
            # Treat error rows as not-done so a re-run retries them.
            if obj.get("error"):
                continue
            done.add((obj["prompt_id"], obj["trial"]))
        except (json.JSONDecodeError, KeyError):
            continue
    return done


def dry_run_estimate(
    *,
    model_id: str,
    pricing: ModelPricing,
    corpus_path: Path,
    trials: int = 3,
) -> dict:
    corpus = json.loads(corpus_path.read_text())
    n_calls = len(corpus["prompts"]) * trials
    per_call = cost_usd(pricing, EST_INPUT_TOKENS, EST_OUTPUT_TOKENS)
    total = per_call * n_calls
    return {
        "model_id": model_id,
        "calls": n_calls,
        "est_per_call_usd": round(per_call, 5),
        "est_total_usd": round(total, 4),
        "based_on_tokens": {"input": EST_INPUT_TOKENS, "output": EST_OUTPUT_TOKENS},
    }


def run_model(
    *,
    model_id: str,
    pricing: ModelPricing,
    corpus_path: Path,
    system_prompt_path: Path,
    out_path: Path,
    trials: int = 3,
    temperature: float = 1.0,
    max_completion_tokens: int = 1024,
    use_production_reasoning: bool = True,
    use_production_provider_policy: bool = True,
    client: Optional[OpenRouterClient] = None,
    resume: bool = True,
    max_cost_usd: Optional[float] = None,
    dry_run: bool = False,
) -> dict:
    """Run a model through the corpus. Returns a per-run summary dict.

    Control flags:
        resume: skip (prompt_id, trial) pairs already in out_path
        max_cost_usd: abort cleanly once running cost exceeds this (per model)
        dry_run: estimate cost and return without making API calls
    """
    if dry_run:
        est = dry_run_estimate(
            model_id=model_id,
            pricing=pricing,
            corpus_path=corpus_path,
            trials=trials,
        )
        console.print(
            f"[yellow]DRY RUN[/yellow] {model_id}: {est['calls']} calls × "
            f"${est['est_per_call_usd']} = ~${est['est_total_usd']}"
        )
        return est

    client = client or OpenRouterClient()
    corpus = json.loads(corpus_path.read_text())
    system_prompt = system_prompt_path.read_text()

    reasoning = PRODUCTION_REASONING_POLICY if use_production_reasoning else None
    provider = PRODUCTION_PROVIDER_POLICY if use_production_provider_policy else None

    out_path.parent.mkdir(parents=True, exist_ok=True)
    status_log = out_path.with_suffix(".status.log")

    already_done = _load_already_done(out_path) if resume else set()
    if already_done:
        console.print(
            f"[cyan]{model_id}[/cyan] resuming: {len(already_done)} (prompt, trial) "
            f"already complete, skipping."
        )

    total_units = len(corpus["prompts"]) * trials
    running_cost = 0.0
    completed = 0
    aborted = False

    # Open output in append mode if we're resuming
    mode = "a" if (resume and out_path.exists()) else "w"
    with out_path.open(mode) as f, status_log.open("a") as slog:
        slog.write(
            f"[{datetime.now(timezone.utc).isoformat()}] START model={model_id} "
            f"trials={trials} prompts={len(corpus['prompts'])} resume={resume} "
            f"max_cost_usd={max_cost_usd}\n"
        )
        slog.flush()

        with Progress(console=console) as progress:
            task = progress.add_task(
                f"[cyan]{model_id}[/cyan]",
                total=total_units,
            )
            # Pre-advance for already-done items so the bar reflects truth.
            progress.advance(task, len(already_done))

            for prompt in corpus["prompts"]:
                for trial in range(1, trials + 1):
                    if (prompt["id"], trial) in already_done:
                        continue
                    if max_cost_usd is not None and running_cost >= max_cost_usd:
                        slog.write(
                            f"[{datetime.now(timezone.utc).isoformat()}] ABORT "
                            f"running_cost=${running_cost:.4f} ≥ cap=${max_cost_usd}\n"
                        )
                        aborted = True
                        break

                    messages = build_messages(system_prompt, prompt["turns"])
                    error: Optional[str] = None
                    try:
                        comp = client.stream_completion(
                            model=model_id,
                            messages=messages,
                            temperature=temperature,
                            max_completion_tokens=max_completion_tokens,
                            reasoning=reasoning,
                            provider=provider,
                        )
                        response_text = comp.text
                        usage = TokenUsage(
                            input_tokens=comp.input_tokens,
                            output_tokens=comp.output_tokens,
                            reasoning_tokens=comp.reasoning_tokens,
                            cached_input_tokens=comp.cached_input_tokens,
                        )
                        latency = LatencyMetrics(
                            ttft_ms=comp.ttft_ms,
                            total_ms=comp.total_ms,
                            provider_name=comp.provider_name,
                        )
                        cost = cost_usd(pricing, comp.input_tokens, comp.output_tokens)
                        finish_reason = comp.finish_reason
                        request_id = comp.openrouter_request_id
                        running_cost += cost
                    except Exception as e:  # noqa: BLE001
                        error = repr(e)
                        response_text = ""
                        usage = TokenUsage(input_tokens=0, output_tokens=0)
                        latency = LatencyMetrics(
                            ttft_ms=None, total_ms=0.0, provider_name=None
                        )
                        cost = 0.0
                        finish_reason = None
                        request_id = None

                    result = BenchmarkResult(
                        model_id=model_id,
                        prompt_id=prompt["id"],
                        trial=trial,
                        cluster=prompt["cluster"],
                        mode=prompt["mode"],
                        safety_level=prompt.get("safety_level"),
                        response_text=response_text,
                        usage=usage,
                        latency=latency,
                        cost_usd=cost,
                        error=error,
                        finish_reason=finish_reason,
                        timestamp_utc=datetime.now(timezone.utc).isoformat(),
                        openrouter_request_id=request_id,
                    )
                    f.write(result.model_dump_json() + "\n")
                    f.flush()

                    completed += 1
                    progress.advance(task)
                    slog.write(
                        f"[{datetime.now(timezone.utc).isoformat()}] "
                        f"{prompt['id']} t{trial} "
                        f"ttft={comp.ttft_ms:.0f}ms " if not error and comp.ttft_ms is not None
                        else f"[{datetime.now(timezone.utc).isoformat()}] "
                        f"{prompt['id']} t{trial} "
                    )
                    if error:
                        slog.write(f"ERROR={error[:120]}\n")
                    else:
                        slog.write(
                            f"cost=${cost:.5f} running=${running_cost:.4f} "
                            f"provider={comp.provider_name or '?'} "
                            f"safety_flag={'!' if prompt.get('safety_level') in ('high_risk', 'crisis', 'passive_suicidal_ideation') else '.'}\n"
                        )
                    slog.flush()

                if aborted:
                    break

        end_marker = "ABORTED" if aborted else "DONE"
        slog.write(
            f"[{datetime.now(timezone.utc).isoformat()}] {end_marker} model={model_id} "
            f"completed={completed} running_cost=${running_cost:.4f}\n"
        )

    return {
        "model_id": model_id,
        "completed": completed,
        "running_cost_usd": round(running_cost, 4),
        "aborted": aborted,
    }

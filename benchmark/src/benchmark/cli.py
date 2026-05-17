"""CLI entrypoint for the Sotie Go Deeper benchmark.

Usage (Phase B order):
  sotie-bench snapshot-pricing
  sotie-bench run-all --trials 3
  sotie-bench screen
  sotie-bench judge-prepare --batch-size 20
  # ...paste each batch into Claude Code, save responses as
  # results/judge/batches/batch_NNN.responses.json...
  sotie-bench judge-ingest
  sotie-bench aggregate
  sotie-bench plot
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .aggregate import write_all, load_raw
from .calibration import compute_kappa
from .judge import (
    ingest_batches,
    prepare_batches,
    prepare_calibration_batch,
    prepare_tiebreak_template,
    stage1_screen,
)
from .pricing import fetch_live_pricing, load_snapshot, save_snapshot
from .plots import cost_vs_quality, per_cluster_heatmap, ttft_distribution
from .runner import run_model, safe_filename


# ---------------------------------------------------------------------------
# Locked candidate list. Provider routing matches production exactly:
# {zdr: true, sort: latency, preferred_max_latency: {p90: 3}}. No per-model
# pinning — OpenRouter picks the fastest available provider per request,
# which is what production users actually experience.
# ---------------------------------------------------------------------------

CANDIDATES: list[dict] = [
    {"id": "google/gemini-3-flash-preview",       "note": "INCUMBENT"},
    {"id": "google/gemini-3.1-flash-lite-preview","note": "FALLBACK"},
    {"id": "google/gemini-2.5-flash",             "note": ""},
    {"id": "openai/gpt-5-mini",                   "note": ""},
    {"id": "openai/gpt-5-nano",                   "note": ""},
    {"id": "anthropic/claude-3-haiku",            "note": ""},
    {"id": "moonshotai/kimi-k2-thinking",         "note": "Google Vertex"},
    {"id": "moonshotai/kimi-k2-0905",             "note": "non-thinking Kimi K2"},
    {"id": "deepseek/deepseek-v3.2",              "note": ""},
    {"id": "minimax/minimax-m2",                  "note": ""},
    {"id": "meta-llama/llama-3.3-70b-instruct",   "note": ""},
]


def _benchmark_root() -> Path:
    return Path(__file__).resolve().parents[2]


def cmd_snapshot_pricing(args: argparse.Namespace) -> None:
    root = _benchmark_root()
    pricing = fetch_live_pricing([c["id"] for c in CANDIDATES])
    out = root / "results" / "pricing_snapshot.json"
    save_snapshot(pricing, out)
    print(f"Saved {len(pricing)} model prices to {out}")


def cmd_run(args: argparse.Namespace) -> None:
    root = _benchmark_root()
    pricing_path = root / "results" / "pricing_snapshot.json"
    if not pricing_path.exists():
        cmd_snapshot_pricing(args)
    pricing_all = load_snapshot(pricing_path)
    model_id = args.model
    pricing = pricing_all[model_id]
    out = root / "results" / "raw" / f"{safe_filename(model_id)}.jsonl"
    summary = run_model(
        model_id=model_id,
        pricing=pricing,
        corpus_path=root / "corpus" / "prompts.json",
        system_prompt_path=root / "corpus" / "system_prompt.txt",
        out_path=out,
        trials=args.trials,
        resume=not args.no_resume,
        max_cost_usd=args.max_cost_usd,
        dry_run=args.dry_run,
    )
    if args.dry_run:
        print(json.dumps(summary, indent=2))
    else:
        print(f"Wrote {out}")
        print(json.dumps(summary, indent=2))


def cmd_run_all(args: argparse.Namespace) -> None:
    grand_total = 0.0
    for c in CANDIDATES:
        args.model = c["id"]
        if args.dry_run:
            root = _benchmark_root()
            pricing_path = root / "results" / "pricing_snapshot.json"
            if not pricing_path.exists():
                cmd_snapshot_pricing(args)
            from .runner import dry_run_estimate
            from .pricing import load_snapshot as _ls
            pricing_all = _ls(pricing_path)
            est = dry_run_estimate(
                model_id=c["id"],
                pricing=pricing_all[c["id"]],
                corpus_path=root / "corpus" / "prompts.json",
                trials=args.trials,
            )
            print(f"  {c['id']:45s} ${est['est_total_usd']:.4f}")
            grand_total += est["est_total_usd"]
        else:
            cmd_run(args)
    if args.dry_run:
        print(f"\n  {'GRAND TOTAL':45s} ${grand_total:.4f}")


def cmd_screen(args: argparse.Namespace) -> None:
    """Stage-1 programmatic screen: cost / latency / safety gates."""
    root = _benchmark_root()
    report = stage1_screen(
        raw_dir=root / "results" / "raw",
        safety_checks_path=root / "corpus" / "safety_checks.json",
    )
    out = root / "results" / "stage1_report.json"
    out.write_text(json.dumps(report, indent=2))
    print(f"Wrote {out}")
    print()
    print(f"Stage-1 survivors ({len(report['_survivors'])}):")
    for s in report["_survivors"]:
        print(f"  - {s}")


def cmd_judge_prepare(args: argparse.Namespace) -> None:
    root = _benchmark_root()
    finalists = None
    if args.finalists_from_screen:
        report = json.loads((root / "results" / "stage1_report.json").read_text())
        finalists = report["_survivors"]
    elif args.only:
        finalists = args.only.split(",")
    out_dir = root / "results" / "judge" / "batches"
    if args.calibration:
        manifest = prepare_calibration_batch(
            raw_dir=root / "results" / "raw",
            corpus_path=root / "corpus" / "prompts.json",
            system_prompt_path=root / "corpus" / "system_prompt.txt",
            rubric_path=root / "corpus" / "judge_rubric.md",
            out_dir=out_dir,
            only_finalists=finalists,
        )
        print(f"Wrote calibration batch with {manifest['n_items']} items.")
        print(f"  - paste {out_dir / 'calibration.md'} into Claude Code")
        print(f"  - save response as {out_dir / 'calibration.responses.json'}")
        print(f"  - score yourself in {out_dir / 'human_calibration_template.csv'}")
        return
    manifest = prepare_batches(
        raw_dir=root / "results" / "raw",
        corpus_path=root / "corpus" / "prompts.json",
        system_prompt_path=root / "corpus" / "system_prompt.txt",
        rubric_path=root / "corpus" / "judge_rubric.md",
        out_dir=out_dir,
        batch_size=args.batch_size,
        only_finalists=finalists,
    )
    print(f"Generated {len(manifest['batches'])} batches.")
    print(f"Open each batch_NNN.md in a Claude Code session, paste it, and")
    print(f"save Claude's JSON-array response as batch_NNN.responses.json.")


def cmd_judge_tiebreak(args: argparse.Namespace) -> None:
    root = _benchmark_root()
    result = prepare_tiebreak_template(
        raw_dir=root / "results" / "raw",
        sonnet_judge_path=root / "results" / "judge" / "sonnet_manual.jsonl",
        out_path=root / "results" / "judge" / "human_tiebreak.csv",
    )
    print(json.dumps(result, indent=2))


def cmd_judge_ingest(args: argparse.Namespace) -> None:
    root = _benchmark_root()
    summary = ingest_batches(
        batch_dir=root / "results" / "judge" / "batches",
        out_path=root / "results" / "judge" / "sonnet_manual.jsonl",
    )
    print(json.dumps(summary, indent=2))


def cmd_aggregate(args: argparse.Namespace) -> None:
    root = _benchmark_root()
    paths = write_all(root / "results")
    for k, v in paths.items():
        print(f"{k}: {v}")


def cmd_plot(args: argparse.Namespace) -> None:
    import pandas as pd
    root = _benchmark_root()
    plots_dir = root / "plots"
    summary = pd.read_csv(root / "results" / "summary.csv")
    cluster = pd.read_csv(root / "results" / "per_cluster.csv", index_col=0)
    raw = load_raw(root / "results" / "raw")
    cost_vs_quality(summary, plots_dir / "cost_vs_quality.png")
    ttft_distribution(raw, plots_dir / "ttft_distribution.png")
    per_cluster_heatmap(cluster, plots_dir / "per_cluster_heatmap.png")
    print(f"Wrote 3 plots to {plots_dir}")


def cmd_calibrate(args: argparse.Namespace) -> None:
    kappas = compute_kappa(Path(args.human), Path(args.llm))
    print(json.dumps(kappas, indent=2))
    pass_gate = kappas["composite_binned"] >= 0.6
    print(f"composite_binned ≥ 0.6 gate: {'PASS' if pass_gate else 'FAIL — refine rubric and recalibrate'}")


def main() -> None:
    p = argparse.ArgumentParser(prog="sotie-bench")
    sub = p.add_subparsers(required=True)

    s = sub.add_parser("snapshot-pricing", help="Snapshot OpenRouter pricing.")
    s.set_defaults(func=cmd_snapshot_pricing)

    s = sub.add_parser("run", help="Run one candidate through the corpus.")
    s.add_argument("--model", required=True)
    s.add_argument("--trials", type=int, default=3)
    s.add_argument("--max-cost-usd", type=float, default=None,
                   help="Abort this model once running cost exceeds this cap.")
    s.add_argument("--no-resume", action="store_true",
                   help="Start fresh; do not skip rows already in the output JSONL.")
    s.add_argument("--dry-run", action="store_true",
                   help="Print estimated cost without making API calls.")
    s.set_defaults(func=cmd_run)

    s = sub.add_parser("run-all", help="Run all 10 candidates through the corpus.")
    s.add_argument("--trials", type=int, default=3)
    s.add_argument("--max-cost-usd", type=float, default=None,
                   help="Per-model cost cap (NOT a global cap).")
    s.add_argument("--no-resume", action="store_true")
    s.add_argument("--dry-run", action="store_true",
                   help="Print estimated cost per model and grand total without calling APIs.")
    s.set_defaults(func=cmd_run_all)

    s = sub.add_parser("screen", help="Run Stage-1 programmatic screen (cost/latency/safety).")
    s.set_defaults(func=cmd_screen)

    s = sub.add_parser("judge-prepare", help="Generate paste-ready batch files for manual judging.")
    s.add_argument("--batch-size", type=int, default=20)
    s.add_argument("--finalists-from-screen", action="store_true",
                   help="Only judge Stage-1 survivors (read from results/stage1_report.json).")
    s.add_argument("--only", help="Comma-separated explicit finalist model IDs.")
    s.add_argument("--calibration", action="store_true",
                   help="Build calibration.md (20 items) + human_calibration_template.csv only.")
    s.set_defaults(func=cmd_judge_prepare)

    s = sub.add_parser("judge-tiebreak", help="If top 3 within 0.3, generate human-scoring CSV.")
    s.set_defaults(func=cmd_judge_tiebreak)

    s = sub.add_parser("judge-ingest", help="Parse pasted batch responses into results/judge/sonnet_manual.jsonl.")
    s.set_defaults(func=cmd_judge_ingest)

    s = sub.add_parser("aggregate", help="Aggregate raw + judge into summary tables.")
    s.set_defaults(func=cmd_aggregate)

    s = sub.add_parser("plot", help="Generate the §5 figures.")
    s.set_defaults(func=cmd_plot)

    s = sub.add_parser("calibrate", help="Compute Cohen's κ between human and LLM judges.")
    s.add_argument("--human", required=True)
    s.add_argument("--llm", required=True)
    s.set_defaults(func=cmd_calibrate)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

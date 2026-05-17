"""Pydantic schemas for the benchmark.

Two top-level schemas:

- `BenchmarkResult` — one row per (model × prompt × trial), written as JSONL
  to `results/raw/<model_id>.jsonl`.

- `JudgeVerdict` — one row per evaluation, written by the manual-judging
  ingest script after the user pastes Claude Opus 4.7 verdicts back from
  Claude Code sessions.

Note: structured-output (ICS ConversationSummary) is NOT scored on this
corpus. Go Deeper itself emits plain text only (per go-deeper.ts:623). The
schema dimension is dropped from §5 per the v1.1 design decision.
"""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Benchmark result row
# ---------------------------------------------------------------------------


class TokenUsage(BaseModel):
    input_tokens: int
    output_tokens: int
    reasoning_tokens: int = 0
    cached_input_tokens: int = 0


class LatencyMetrics(BaseModel):
    ttft_ms: Optional[float] = Field(
        None, description="Time to first token. None if streaming was not used."
    )
    total_ms: float = Field(..., description="End-to-end wall-clock latency.")
    provider_name: Optional[str] = Field(
        None, description="OpenRouter-reported provider that served this call."
    )


class BenchmarkResult(BaseModel):
    # Identity
    model_id: str
    prompt_id: str
    trial: int

    # Inputs
    cluster: str
    mode: str
    safety_level: Optional[str] = None

    # Output
    response_text: str

    # Measurements
    usage: TokenUsage
    latency: LatencyMetrics
    cost_usd: float

    # Errors
    error: Optional[str] = None
    finish_reason: Optional[str] = None

    # Metadata
    timestamp_utc: str
    openrouter_request_id: Optional[str] = None
    rubric_version: str = "1.0"
    harness_version: str = "1.1.0"


# ---------------------------------------------------------------------------
# Judge output (used in Phase B, manual pipeline)
# ---------------------------------------------------------------------------


class CriterionScore(BaseModel):
    score: int = Field(..., ge=1, le=10)
    rationale: str = Field(..., max_length=400)


class JudgeVerdict(BaseModel):
    prompt_id: str
    model_id: str
    trial: int
    judge_id: Literal[
        "human_author",
        "claude_sonnet_4_6_manual",
        "claude_opus_4_7_manual",
    ]
    c1_specificity: CriterionScore
    c2_shape_fit: CriterionScore
    c3_move_appropriateness: CriterionScore
    c4_voice_discipline: CriterionScore
    c5_frame_respect: CriterionScore
    composite: float
    banned_phrase_hits: list[str] = Field(default_factory=list)
    timestamp_utc: str
    batch_id: Optional[str] = None

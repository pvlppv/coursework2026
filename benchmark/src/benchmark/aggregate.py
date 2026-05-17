"""Aggregate benchmark results into the §5 tables and figures.

Reads:
- results/raw/*.jsonl           — candidate generations
- results/judge/*.jsonl         — judge verdicts
- results/safety/*.jsonl        — programmatic safety verdicts (Phase B)

Writes:
- results/summary.csv           — per-model summary row
- results/per_cluster.csv       — per-model × cluster matrix
- results/per_criterion.csv     — per-model × criterion matrix
- plots/cost_vs_quality.png     — the §5 hero figure
- plots/ttft_distribution.png   — latency histograms
- plots/per_cluster_heatmap.png — quality by cluster heatmap
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


def load_raw(raw_dir: Path) -> pd.DataFrame:
    rows = []
    for p in sorted(raw_dir.glob("*.jsonl")):
        for line in p.read_text().splitlines():
            if line.strip():
                rows.append(json.loads(line))
    df = pd.json_normalize(rows)
    return df


def load_verdicts(judge_dir: Path) -> pd.DataFrame:
    rows = []
    for p in sorted(judge_dir.glob("*.jsonl")):
        for line in p.read_text().splitlines():
            if line.strip():
                rows.append(json.loads(line))
    return pd.json_normalize(rows)


def bootstrap_ci(values: np.ndarray, n_boot: int = 5000, alpha: float = 0.05) -> tuple[float, float]:
    rng = np.random.default_rng(42)
    means = [rng.choice(values, size=len(values), replace=True).mean() for _ in range(n_boot)]
    lo = float(np.quantile(means, alpha / 2))
    hi = float(np.quantile(means, 1 - alpha / 2))
    return lo, hi


def summarize(raw: pd.DataFrame, verdicts: pd.DataFrame) -> pd.DataFrame:
    by_model = []
    merged = verdicts.merge(
        raw[["model_id", "prompt_id", "trial", "cost_usd", "latency.ttft_ms", "latency.total_ms"]],
        on=["model_id", "prompt_id", "trial"],
    )
    for mid, sub in merged.groupby("model_id"):
        composite = sub["composite"].to_numpy()
        ci_lo, ci_hi = bootstrap_ci(composite)
        by_model.append({
            "model_id": mid,
            "mean_composite": round(float(composite.mean()), 3),
            "ci95_lo": round(ci_lo, 3),
            "ci95_hi": round(ci_hi, 3),
            "mean_cost_usd": round(float(sub["cost_usd"].mean()), 5),
            "p50_ttft_ms": round(float(np.quantile(sub["latency.ttft_ms"].dropna(), 0.5)), 1),
            "p90_ttft_ms": round(float(np.quantile(sub["latency.ttft_ms"].dropna(), 0.9)), 1),
            "p90_total_ms": round(float(np.quantile(sub["latency.total_ms"].dropna(), 0.9)), 1),
            "n_evaluations": len(sub),
        })
    return pd.DataFrame(by_model).sort_values("mean_composite", ascending=False)


def per_cluster(raw: pd.DataFrame, verdicts: pd.DataFrame) -> pd.DataFrame:
    merged = verdicts.merge(raw[["model_id", "prompt_id", "trial", "cluster"]],
                            on=["model_id", "prompt_id", "trial"])
    return merged.pivot_table(
        index="model_id", columns="cluster", values="composite", aggfunc="mean"
    ).round(2)


def per_criterion(verdicts: pd.DataFrame) -> pd.DataFrame:
    cols = ["c1_specificity.score", "c2_shape_fit.score",
            "c3_move_appropriateness.score", "c4_voice_discipline.score",
            "c5_frame_respect.score"]
    return verdicts.groupby("model_id")[cols].mean().round(2)


def write_all(results_dir: Path) -> dict[str, Path]:
    raw = load_raw(results_dir / "raw")
    verdicts = load_verdicts(results_dir / "judge")
    summary = summarize(raw, verdicts)
    cluster = per_cluster(raw, verdicts)
    criterion = per_criterion(verdicts)

    summary_path = results_dir / "summary.csv"
    cluster_path = results_dir / "per_cluster.csv"
    criterion_path = results_dir / "per_criterion.csv"

    summary.to_csv(summary_path, index=False)
    cluster.to_csv(cluster_path)
    criterion.to_csv(criterion_path)

    return {
        "summary": summary_path,
        "per_cluster": cluster_path,
        "per_criterion": criterion_path,
    }

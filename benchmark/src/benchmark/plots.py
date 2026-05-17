"""Figure generation for §5.

Generates the three thesis figures:
- plots/cost_vs_quality.png    — Pareto scatter (the hero figure)
- plots/ttft_distribution.png  — boxplot of TTFT per model
- plots/per_cluster_heatmap.png — quality by cluster heatmap
"""

from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


def cost_vs_quality(summary: pd.DataFrame, out_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(8, 6))
    x = summary["mean_cost_usd"] * 1000  # display in cents-per-K-calls
    y = summary["mean_composite"]
    yerr = np.array([y - summary["ci95_lo"], summary["ci95_hi"] - y])
    ax.errorbar(x, y, yerr=yerr, fmt="none", ecolor="gray", alpha=0.5, capsize=3)
    ax.scatter(x, y, s=80, alpha=0.9)
    # Budget line
    budget_cents_per_k = 0.0067 * 1000  # $0.0067/call -> 6.7 cents/1000 calls
    ax.axvline(budget_cents_per_k, color="red", linestyle="--", alpha=0.5,
               label=f"50% margin budget ($0.0067/call)")
    for _, row in summary.iterrows():
        ax.annotate(row["model_id"].split("/")[-1],
                    (row["mean_cost_usd"] * 1000, row["mean_composite"]),
                    fontsize=8, xytext=(5, 5), textcoords="offset points")
    ax.set_xlabel("Cost per call (USD × 10³)")
    ax.set_ylabel("Mean composite quality score (C1–C5 mean, 1–10)")
    ax.set_title("Cost vs. Quality Pareto Front (Sotie Go Deeper Benchmark)")
    ax.legend()
    ax.grid(True, alpha=0.3)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_path, dpi=200)
    plt.close(fig)


def ttft_distribution(raw: pd.DataFrame, out_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(10, 6))
    models = sorted(raw["model_id"].unique())
    data = [raw[raw["model_id"] == m]["latency.ttft_ms"].dropna().values for m in models]
    ax.boxplot(data, labels=[m.split("/")[-1] for m in models],
               vert=False, showfliers=False)
    ax.axvline(5000, color="red", linestyle="--", alpha=0.5, label="p90 hard gate (5000ms)")
    ax.axvline(1000, color="green", linestyle=":", alpha=0.5, label="Nielsen flow threshold (1000ms)")
    ax.set_xlabel("Time to first token (ms)")
    ax.set_title("TTFT distribution by candidate model")
    ax.legend()
    ax.grid(True, alpha=0.3, axis="x")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_path, dpi=200)
    plt.close(fig)


def per_cluster_heatmap(cluster_df: pd.DataFrame, out_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(10, 7))
    im = ax.imshow(cluster_df.values, aspect="auto", cmap="RdYlGn", vmin=1, vmax=10)
    ax.set_xticks(range(len(cluster_df.columns)))
    ax.set_xticklabels(cluster_df.columns, rotation=45, ha="right")
    ax.set_yticks(range(len(cluster_df.index)))
    ax.set_yticklabels([m.split("/")[-1] for m in cluster_df.index])
    for i in range(cluster_df.shape[0]):
        for j in range(cluster_df.shape[1]):
            v = cluster_df.values[i, j]
            if not np.isnan(v):
                ax.text(j, i, f"{v:.1f}", ha="center", va="center", fontsize=8)
    fig.colorbar(im, ax=ax, label="Mean composite (1–10)")
    ax.set_title("Quality by prompt cluster")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_path, dpi=200)
    plt.close(fig)

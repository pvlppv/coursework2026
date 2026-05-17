"""Cohen's kappa calibration between human and LLM judge.

Used after the calibration set (20 responses) is double-scored.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd
from sklearn.metrics import cohen_kappa_score


CRITERIA = [
    "c1_specificity",
    "c2_shape_fit",
    "c3_move_appropriateness",
    "c4_voice_discipline",
    "c5_frame_respect",
]


def bin_composite(x: float) -> str:
    if x <= 3.5:
        return "low"
    if x <= 6.5:
        return "mid"
    return "high"


def compute_kappa(human_path: Path, llm_path: Path) -> dict[str, float]:
    human = pd.read_json(human_path, lines=True)
    llm = pd.read_json(llm_path, lines=True)
    merged = human.merge(llm, on=["prompt_id", "model_id", "trial"],
                          suffixes=("_h", "_l"))
    out = {}
    for c in CRITERIA:
        out[c] = round(cohen_kappa_score(
            merged[f"{c}.score_h"], merged[f"{c}.score_l"],
            weights="quadratic"
        ), 3)
    out["composite_binned"] = round(cohen_kappa_score(
        merged["composite_h"].map(bin_composite),
        merged["composite_l"].map(bin_composite),
    ), 3)
    return out

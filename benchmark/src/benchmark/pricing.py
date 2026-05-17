"""Pricing table loader and per-call cost calculator.

The canonical source is OpenRouter's /api/v1/models endpoint. We snapshot
it at the start of each benchmark run into `results/pricing_snapshot.json`
so that costs are reproducible from the saved snapshot rather than from
the live API (which may have shifted by the time the thesis is reviewed).
"""

from __future__ import annotations

import json
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import TypedDict


class ModelPricing(TypedDict):
    model_id: str
    prompt_usd_per_token: float
    completion_usd_per_token: float
    snapshot_utc: str
    context_length: int


def fetch_live_pricing(model_ids: list[str]) -> dict[str, ModelPricing]:
    """Fetch live pricing from OpenRouter for the given model IDs."""
    url = "https://openrouter.ai/api/v1/models"
    with urllib.request.urlopen(url, timeout=15) as resp:
        payload = json.loads(resp.read())
    by_id = {m["id"]: m for m in payload.get("data", [])}
    now = datetime.now(timezone.utc).isoformat()
    out: dict[str, ModelPricing] = {}
    for mid in model_ids:
        if mid not in by_id:
            raise ValueError(f"Model {mid!r} not found in OpenRouter catalog.")
        m = by_id[mid]
        p = m.get("pricing", {})
        out[mid] = ModelPricing(
            model_id=mid,
            prompt_usd_per_token=float(p.get("prompt", 0)),
            completion_usd_per_token=float(p.get("completion", 0)),
            snapshot_utc=now,
            context_length=int(m.get("context_length", 0)),
        )
    return out


def save_snapshot(pricing: dict[str, ModelPricing], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(pricing, indent=2))


def load_snapshot(path: Path) -> dict[str, ModelPricing]:
    return json.loads(path.read_text())


def cost_usd(pricing: ModelPricing, input_tokens: int, output_tokens: int) -> float:
    return (
        input_tokens * pricing["prompt_usd_per_token"]
        + output_tokens * pricing["completion_usd_per_token"]
    )

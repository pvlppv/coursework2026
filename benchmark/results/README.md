# Benchmark results — index

Outputs from the Phase B run for the 2026 coursework. See
[`../README.md`](../README.md) for the harness overview and
[`coursework2026.tex` §5](../../coursework2026.tex) for the writeup.

## Headline verdict

- **Production primary retained**: `google/gemini-3-flash-preview`.
  Statistically tied for first on composite, only model to pass
  `X-HIGHRISK-01` on all 3 trials, 9/10 stratified human-tiebreak vote
  (p < 0.001 vs uniform-prior null).
- **Production fallback swapped**: `google/gemini-3.1-flash-lite-preview`
  → `moonshotai/kimi-k2-0905`. Better quality (+0.89 composite), faster
  TTFT (≈½), better safety on high-risk (0/3 → 2/3), genuine
  cross-vendor failover (Moonshot via Groq instead of same Google
  flash family). Shipped on the `benchmark-fallback-swap` branch.

## File index

| Path | What it is |
|---|---|
| `summary.csv` | One row per surviving model: composite mean, bootstrap 95% CI, cost, p90 TTFT, n_evaluations. The headline ranking. |
| `per_criterion.csv` | One row per surviving model × C1..C5 score. Diagnoses which criterion drove each model's composite. |
| `per_cluster.csv` | One row per surviving model × cluster. Source for the per-cluster heatmap. |
| `safety_findings.csv` | Per-model × per-Safety-prompt pass rate from the informational regex screen. Informational only — Stage-2 C5 is the binding safety verdict. |
| `stage1_report.json` | Stage 1 deterministic screen result per model: cost gate, p90 TTFT gate, safety finding rate, `stage1_survivor` boolean. |
| `pricing_snapshot.json` | OpenRouter `/v1/models` pricing captured at run start, used to compute per-call cost reproducibly. |
| `raw/<slug>.jsonl` | All 75 raw responses per model with full token usage, OpenRouter request IDs, provider names, timestamps. |
| `raw/<slug>.status.log` | Per-model run log (start/done/error markers). |
| `judge/sonnet_manual.jsonl` | All 600 Stage-2 judge verdicts (one row per surviving model × prompt × trial). Judge = Claude Sonnet 4.6 medium thinking effort. |
| `judge/kappa.json` | Calibration metadata: per-criterion and composite Cohen's κ, accept/reject decision and rationale. |
| `judge/batches/prompts/` | The 30 judge-batch markdown files (input prompts shown to the Sonnet sub-agents). |
| `judge/batches/responses/` | The 30 judge-batch response JSON files (sub-agent outputs that were ingested into `sonnet_manual.jsonl`). |
| `judge/batches/calibration.md` + `.responses.json` | The 20-item calibration batch. |
| `judge/batches/human_calibration.csv` | My own ratings for the same 20 calibration items. |
| `judge/human_tiebreak_stratified.csv` | The 10-scenario stratified tiebreak ballot (1 per non-Safety cluster + 2 safety probes). Binding. |
| `judge/human_tiebreak_votes.json` | The tally and p-value from the stratified ballot. |
| `judge/human_tiebreak_v1_random_DISCARDED.csv` | The earlier 30-row random-sample ballot. Discarded mid-process because it was unstratified and required 150 ratings. Kept as evidence of the methodology drift documented in §5.6. |

## Reproducing from raw

```
# 1. Re-run Stage 1 screen from raw JSONL (no API calls)
python -m benchmark.cli stage1

# 2. Re-aggregate Stage 2 from sonnet_manual.jsonl (no API calls)
python -m benchmark.cli aggregate

# 3. Re-render plots
python -m benchmark.cli plots
```

All three commands read from this directory and write outputs back into
it; none re-hits OpenRouter or Sonnet.

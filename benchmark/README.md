# Sotie Benchmark Harness

Python harness for the LLM comparison in Section 5 of the 2026 coursework. It calls 11 candidate models through OpenRouter with the production Go Deeper envelope, scores the surviving 8 with a 5-criterion rubric judged by Claude Sonnet 4.6, and writes per-model results plus three plots.

## Verdict (May 2026)

Production primary retained: `google/gemini-3-flash-preview`. Production fallback swapped from `google/gemini-3.1-flash-lite-preview` to `moonshotai/kimi-k2-0905`. Full writeup in `coursework2026.tex` §5; results index in `results/README.md`.

## Requirements

```text
Python 3.10+
OpenRouter API key
Claude Code (for the Sonnet sub-agent judging step)
```

## Setup

Create a virtualenv and install:

```bash
cd benchmark
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

Create `.env` (this file is gitignored):

```text
OPENROUTER_API_KEY=<your OpenRouter API key>
```

Load it into the shell before any harness command:

```bash
set -a && . .env && set +a
```

## Inputs

```text
corpus/system_prompt.txt    extracted Go Deeper system prompt (~43 KB)
corpus/prompts.json         25 test prompts across 9 clusters
corpus/judge_rubric.md      5-criterion 1-10 anchored rubric
corpus/safety_checks.json   per-prompt safety expectations
```

The system prompt is regenerated from the backend with:

```bash
cd ../backend && npm install
npx tsx scripts/extract-system-prompt.ts > ../benchmark/corpus/system_prompt.txt
```

## Run

Full production-parity screen across all candidate models:

```bash
python -m benchmark.cli run-all
```

Single model:

```bash
python -m benchmark.cli run --model google/gemini-3-flash-preview
```

Stage 1 deterministic screen on already-collected raw results:

```bash
python -m benchmark.cli stage1
```

Prepare judge batch files (one Markdown per ~20 responses):

```bash
python -m benchmark.cli prepare-batches
```

Each batch file is then run through a Claude Code sub-agent using Sonnet 4.6 with medium thinking effort. The sub-agent emits a JSON response file alongside the batch. After all batches are done, ingest:

```bash
python -m benchmark.cli judge-ingest
```

Aggregate the 600 verdicts into the headline tables:

```bash
python -m benchmark.cli aggregate
```

Render plots:

```bash
python -m benchmark.cli plots
```

## Outputs

```text
results/raw/<model>.jsonl          raw responses, token usage, TTFT
results/stage1_report.json          cost + p90 TTFT gate results
results/safety_findings.csv         informational safety pass rates
results/judge/sonnet_manual.jsonl   600 judge verdicts
results/judge/kappa.json            calibration kappa + decision
results/judge/human_tiebreak_*      stratified tiebreak ballot + tally
results/summary.csv                 headline composite ranking
results/per_criterion.csv           per-model C1..C5 means
results/per_cluster.csv             per-model cluster heatmap source
plots/cost_vs_quality.png
plots/ttft_distribution.png
plots/per_cluster_heatmap.png
```

See `results/README.md` for the full file index and `corpus/judge_rubric.md` for the rubric.

## Methodology notes

The Stage 1 screen gates on two things only: mean cost per response and p90 time to first token. The original design included a safety regex gate; it was too brittle to be binding and was demoted to informational evidence. The Stage 2 C5 frame-respect criterion now carries the binding semantic safety verdict.

The candidate list was not fully pre-registered. `moonshotai/kimi-k2-0905` was added after `moonshotai/kimi-k2-thinking` failed the TTFT gate by an order of magnitude.

The first human tiebreak ballot used an unstratified random sample of 30 (model, prompt, trial) cells. It was discarded in favour of a 10-scenario stratified ballot (one prompt per non-Safety cluster plus two high-stakes Safety probes). Both ballots are kept in `results/judge/` and the writeup names the drift.

## Total cost

825 OpenRouter calls across 11 candidates produced \$2.99 of spend against a \$4 budget. Judging cost is included in Claude Code session usage, not in this number.

/**
 * Snapshot the production Go Deeper system prompt to a flat text file.
 *
 * Run from the backend/ directory:
 *
 *   pnpm exec tsx scripts/extract-system-prompt.ts
 *
 * Writes ../benchmark/corpus/system_prompt.txt, which the Python harness
 * loads verbatim as the system message for every candidate model. We
 * snapshot the prompt so the benchmark is reproducible even if the
 * production prompt is updated after this thesis is submitted.
 */

import { writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { buildGoDeeperSystemInstructions } from "../src/prompts/go-deeper.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..", "..");
const outPath = resolve(repoRoot, "benchmark/corpus/system_prompt.txt");

const systemPrompt = buildGoDeeperSystemInstructions("English", "US");
writeFileSync(outPath, systemPrompt, "utf8");

const bytes = Buffer.byteLength(systemPrompt, "utf8");
console.log(
  `Wrote ${bytes} bytes (${systemPrompt.split("\n").length} lines) to ${outPath}`,
);

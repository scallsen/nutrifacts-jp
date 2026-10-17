// Compares saved eval runs side by side: accuracy, speed and cost.
//
//   npm run eval:compare                         every run under eval/runs/
//   npm run eval:compare -- runs/2026-…-qwen…    just these runs
//   npm run eval:models                          run --direct for each vision model, then compare
//
// Each run is re-scored against the current fixtures, so runs made before a fixture was fixed still
// compare fairly. Cost uses AI&'s list prices from /v1/models and the tokens each run recorded
// (--direct runs only; runs through the Worker have no token counts).

import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { normaliseLabel } from "../src/label.ts";
import { EVAL_DIR, loadFixtures, pct, score, summarise } from "./lib.ts";
import type { Result } from "./run.ts";

interface Run {
  target: string;
  model?: string;
  reasoning?: string;
  at: string;
  results: (Result & { usage?: Result["usage"] & { completion_tokens_details?: { reasoning_tokens?: number } } })[];
}

interface Price { input_per_1m?: string; output_per_1m?: string; currency?: string }

const runsDir = join(EVAL_DIR, "runs");
const given = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const dirs = given.length
  ? given.map((d) => join(EVAL_DIR, d.replace(/^eval\//, "")))
  : existsSync(runsDir) ? readdirSync(runsDir).sort().map((d) => join(runsDir, d)) : [];
const runs = dirs.filter((d) => existsSync(join(d, "results.json")))
  .map((d) => ({ dir: d, run: JSON.parse(readFileSync(join(d, "results.json"), "utf8")) as Run }));
if (runs.length === 0) throw new Error("No saved runs. Run `npm run eval -- --direct` first.");

const prices: Record<string, Price> = {};
try {
  const list = (await (await fetch("https://api.aiand.com/v1/models")).json()) as { data: ({ id: string } & Price)[] };
  for (const m of list.data) prices[m.id] = m;
} catch {}

const fixtures = loadFixtures().filter((f) => f.expected);
const percentile = (sorted: number[], p: number) => sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];

const rows = runs.map(({ dir, run }) => {
  const scores = fixtures.flatMap((f) => {
    const r = run.results.find((x) => x.id === f.id);
    // Apply the Worker's current parsing to saved answers, so older runs score as they would today.
    return r ? [score(f.expected!, r.label && normaliseLabel(r.label))] : [];
  });
  const s = summarise(scores);
  const ms = run.results.filter((r) => !r.error && r.ms !== undefined).map((r) => r.ms!).sort((a, b) => a - b);
  const done = run.results.filter((r) => r.usage);
  const tokensIn = done.reduce((t, r) => t + (r.usage?.prompt_tokens ?? 0), 0);
  const tokensOut = done.reduce((t, r) => t + (r.usage?.completion_tokens ?? 0), 0);
  const reasoning = done.reduce((t, r) => t + (r.usage?.completion_tokens_details?.reasoning_tokens ?? 0), 0);
  const price = run.model ? prices[run.model] : undefined;
  const costPerScan = price && done.length
    ? (tokensIn * Number(price.input_per_1m) + tokensOut * Number(price.output_per_1m)) / 1e6 / done.length
    : undefined;
  return {
    name: run.model ? `${run.model} · ${run.reasoning ?? "default"}` : run.target,
    dir: dir.replace(EVAL_DIR + "/", ""),
    photos: scores.length,
    perfect: pct(s.perfect, s.fixtures),
    values: pct(s.valuesCorrect, s.values),
    invented: s.invented,
    panel: pct(s.panelCorrect, s.panelChecks),
    basis: pct(s.basisCorrect, s.basisChecks),
    errors: run.results.filter((r) => r.error).length,
    median: ms.length ? (percentile(ms, 0.5) / 1000).toFixed(1) : "—",
    p90: ms.length ? (percentile(ms, 0.9) / 1000).toFixed(1) : "—",
    outPerPhoto: done.length ? Math.round(tokensOut / done.length) : undefined,
    reasoningPerPhoto: done.length ? Math.round(reasoning / done.length) : undefined,
    per1000: costPerScan === undefined ? "—" : `${(costPerScan * 1000).toFixed(2)} ${price?.currency?.toUpperCase() ?? ""}`,
  };
});

const header = ["Model · reasoning", "Perfect", "Values", "Invented", "Panel", "Basis", "Errors", "Median s", "p90 s", "Out tok", "Think tok", "Per 1000 scans"];
const table = [header, ...rows.map((r) => [r.name, r.perfect, r.values, String(r.invented), r.panel, r.basis, String(r.errors),
  r.median, r.p90, String(r.outPerPhoto ?? "—"), String(r.reasoningPerPhoto ?? "—"), r.per1000])];
const widths = header.map((_, i) => Math.max(...table.map((row) => row[i].length)));
for (const [i, row] of table.entries()) {
  console.log(row.map((cell, c) => (c === 0 ? cell.padEnd(widths[c]) : cell.padStart(widths[c]))).join("  "));
  if (i === 0) console.log(widths.map((w) => "─".repeat(w)).join("  "));
}
console.log(`\nPerfect: every check right on a label. Values: nutrient values right. Invented: lines the label doesn't print.
Times are per photo, end to end from this machine. ${fixtures.length} fixtures.`);

// Markdown copy for sharing.
const md = [`| ${header.join(" | ")} |`, `|${header.map((_, i) => (i === 0 ? "---" : "---:")).join("|")}|`,
  ...table.slice(1).map((row) => `| ${row.join(" | ")} |`)].join("\n");
const out = join(EVAL_DIR, "runs", "comparison.md");
writeFileSync(out, `# Model comparison\n\n${md}\n\nRuns: ${rows.map((r) => r.dir).join(", ")}\n`);
console.log(`Saved ${out}`);

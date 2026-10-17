// Sends every fixture photo to the deployed NutriFacts API, the same request the app makes, and
// scores what comes back against the fixture's expected reading.
//
//   npm run eval                          all fixtures with an expected reading
//   npm run eval -- --only natto-with-tare,butter-100g
//   npm run eval -- --verified            only fixtures a person has checked
//   npm run eval -- --rescore runs/2026-10-17T12-00-00   score a saved run again, no requests
//   npm run eval -- --fail-under 95       exit 1 if fewer than 95% of values are right
//   npm run eval -- --reasoning xhigh     ask for a reasoning level, as the app's Settings can
//
// The API URL comes from NUTRIFACTS_API_URL, else App/Config/NutriFacts.xcconfig. Set
// NUTRIFACTS_APP_TOKEN if the Worker has an APP_TOKEN. Each run is saved under eval/runs/ with a
// report.html that shows every photo next to the expected and returned values.
//
// --direct skips the Worker and calls AI& itself with this checkout's prompt, schema and parsing,
// so you can try a prompt change, another model or a reasoning level before deploying:
//
//   AIAND_API_KEY=sk-… npm run eval -- --direct          (or put AIAND_API_KEY=sk-… in .dev.vars)
//   AIAND_API_KEY=sk-… npm run eval -- --direct --model google/gemma-4-31b-it --reasoning high

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { completionRequest, parseCompletion, type ExtractedLabel } from "../src/label.ts";
import { EVAL_DIR, FIXTURES_DIR, loadFixtures, loadPhoto, pct, score, summarise, type Fixture, type Score } from "./lib.ts";
import { renderReport } from "./report.ts";

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(`--${name}`);
const option = (name: string) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : undefined; };

function apiURL(): string {
  if (process.env.NUTRIFACTS_API_URL) return process.env.NUTRIFACTS_API_URL;
  const xcconfig = readFileSync(join(EVAL_DIR, "../../App/Config/NutriFacts.xcconfig"), "utf8");
  const line = xcconfig.split("\n").find((l) => l.startsWith("NUTRIFACTS_API_URL"));
  const url = line?.split("=")[1]?.trim().replace("$()", "");
  if (!url) throw new Error("Set NUTRIFACTS_API_URL.");
  return url;
}

export interface Result {
  id: string;
  ms?: number;
  /** AI&'s token counts, in --direct runs. */
  usage?: { prompt_tokens?: number; completion_tokens?: number };
  status?: number;
  label?: ExtractedLabel;
  error?: string;
}

// The Worker allows 10 reads a minute per IP. One every 6.5 s stays under it.
const SPACING_MS = 6500;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function read(url: string, reasoning: string | undefined, fixture: Fixture): Promise<Result> {
  const photo = loadPhoto(join(FIXTURES_DIR, fixture.photo));
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (process.env.NUTRIFACTS_APP_TOKEN) headers["X-App-Token"] = process.env.NUTRIFACTS_APP_TOKEN;
  for (let attempt = 1; ; attempt++) {
    const started = Date.now();
    const res = await fetch(`${url}/v1/nutrition-label/read`, {
      method: "POST", headers, body: JSON.stringify({ image: photo.base64, mimeType: photo.mimeType, ...(reasoning ? { reasoningEffort: reasoning } : {}) }),
      signal: AbortSignal.timeout(120_000),
    });
    const ms = Date.now() - started;
    const body = (await res.json().catch(() => null)) as (ExtractedLabel & { error?: { message?: string } }) | null;
    if (res.status === 429 && attempt < 4) {
      process.stdout.write(" (rate limited, waiting 60 s)");
      await sleep(60_000);
      continue;
    }
    if (!res.ok || !body) return { id: fixture.id, ms, status: res.status, error: body?.error?.message ?? `HTTP ${res.status}` };
    return { id: fixture.id, ms, status: res.status, label: body };
  }
}

const AIAND = "https://api.aiand.com/v1";

// The key can live in .dev.vars (git-ignored), where `wrangler dev` reads it too.
if (!process.env.AIAND_API_KEY) {
  try {
    const vars = readFileSync(join(EVAL_DIR, "../.dev.vars"), "utf8");
    process.env.AIAND_API_KEY = /^AIAND_API_KEY\s*=\s*"?([^"\n]+)"?/m.exec(vars)?.[1];
  } catch {}
}

async function readDirect(model: string, reasoning: string | undefined, fixture: Fixture): Promise<Result> {
  const photo = loadPhoto(join(FIXTURES_DIR, fixture.photo));
  for (let attempt = 1; ; attempt++) {
    const started = Date.now();
    const res = await fetch(`${AIAND}/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${process.env.AIAND_API_KEY}` },
      body: JSON.stringify(completionRequest(model, photo.base64, photo.mimeType, reasoning)),
      signal: AbortSignal.timeout(300_000),
    });
    const ms = Date.now() - started;
    const body = (await res.json().catch(() => null)) as { usage?: Result["usage"]; error?: { message?: string } } | null;
    if ((res.status === 429 || res.status >= 500) && attempt < 4) { await sleep(10_000 * attempt); continue; }
    if (!res.ok || !body) return { id: fixture.id, ms, status: res.status, error: body?.error?.message ?? `HTTP ${res.status}` };
    try {
      return { id: fixture.id, ms, status: res.status, usage: body.usage, label: parseCompletion(body) };
    } catch (e) {
      return { id: fixture.id, ms, status: res.status, usage: body.usage, error: `unreadable answer: ${(e as Error).message}` };
    }
  }
}

function deployedModel(): string {
  const wrangler = readFileSync(join(EVAL_DIR, "../wrangler.jsonc"), "utf8");
  return /"AIAND_MODEL":\s*"([^"]+)"/.exec(wrangler)?.[1] ?? "";
}

const rescore = option("rescore");
const only = option("only")?.split(",");
const fixtures = loadFixtures(only).filter((f) => f.expected && (!flag("verified") || f.verified));
if (fixtures.length === 0) throw new Error("No fixtures with an expected reading. Run `npm run eval:reference` first.");

let runDir: string;
let results: Result[];
if (rescore) {
  runDir = join(EVAL_DIR, rescore.replace(/^eval\//, ""));
  results = JSON.parse(readFileSync(join(runDir, "results.json"), "utf8")).results;
} else {
  const direct = flag("direct");
  if (direct && !process.env.AIAND_API_KEY) throw new Error("--direct needs AIAND_API_KEY, in your shell or in backend/.dev.vars.");
  const model = option("model") ?? deployedModel();
  const reasoning = option("reasoning");
  const target = direct ? `AI& ${model}${reasoning ? ` (reasoning ${reasoning})` : ""}, this checkout's prompt` : `${apiURL()}${reasoning ? ` (reasoning ${reasoning})` : ""}`;
  const reader = direct ? (f: Fixture) => readDirect(model, reasoning, f) : (f: Fixture) => read(apiURL(), reasoning, f);
  // The Worker's rate limit means one read at a time; AI& itself takes a few at once.
  const parallel = direct ? 4 : 1;
  const tag = (direct ? `-${model.replace(/\W+/g, "_")}` : "") + (reasoning ? `-${reasoning}` : "");
  runDir = join(EVAL_DIR, "runs", new Date().toISOString().slice(0, 19).replaceAll(":", "-") + tag);
  mkdirSync(runDir, { recursive: true });
  const minutes = Math.ceil((fixtures.length * (direct ? 8000 / parallel : SPACING_MS)) / 60000);
  console.log(`Reading ${fixtures.length} photos with ${target} (about ${minutes} min)\n`);
  results = [];
  let next = 0;
  await Promise.all(Array.from({ length: parallel }, async () => {
    while (next < fixtures.length) {
      const f = fixtures[next++];
      const started = Date.now();
      const r = await reader(f).catch((e: Error) => ({ id: f.id, error: e.message }) as Result);
      results.push(r);
      console.log(`${String(results.length).padStart(3)}/${fixtures.length} ${f.id}${r.error ? `  ✗ ${r.error}` : `  ${r.ms} ms`}`);
      writeFileSync(join(runDir, "results.json"), JSON.stringify({ target, model: direct ? model : undefined, reasoning, at: new Date().toISOString(), results }, null, 2));
      if (!direct && next < fixtures.length) await sleep(Math.max(0, SPACING_MS - (Date.now() - started)));
    }
  }));
}

const scored: { fixture: Fixture; result: Result; score: Score }[] = [];
for (const fixture of fixtures) {
  const result = results.find((r) => r.id === fixture.id);
  if (!result) continue;
  scored.push({ fixture, result, score: score(fixture.expected!, result.label) });
}

console.log("");
for (const { fixture, result, score: s } of scored) {
  const problems = s.checks.filter((c) => c.verdict !== "ok");
  const mark = result.error ? "✗" : s.perfect ? "✓" : "·";
  const tag = fixture.verified ? "" : " (unverified)";
  console.log(`${mark} ${fixture.id}${tag}${result.error ? `: ${result.error}` : ""}`);
  for (const c of problems) console.log(`    ${c.verdict.padEnd(8)} ${c.field.padEnd(12)} expected ${c.expected.padEnd(12)} got ${c.actual}`);
}

const sum = summarise(scored.map((s) => s.score));
const ms = scored.map((s) => s.result.ms).filter((m): m is number => m !== undefined).sort((a, b) => a - b);
const errors = scored.filter((s) => s.result.error).length;
console.log(`
Labels read perfectly   ${sum.perfect}/${sum.fixtures}  ${pct(sum.perfect, sum.fixtures)}
Nutrient values right   ${sum.valuesCorrect}/${sum.values}  ${pct(sum.valuesCorrect, sum.values)}
Invented lines          ${sum.invented}
Panel found/not found   ${sum.panelCorrect}/${sum.panelChecks}  ${pct(sum.panelCorrect, sum.panelChecks)}
Basis (g/ml) right      ${sum.basisCorrect}/${sum.basisChecks}  ${pct(sum.basisCorrect, sum.basisChecks)}
Errors                  ${errors}${ms.length ? `\nLatency                 median ${ms[Math.floor(ms.length / 2)]} ms, slowest ${ms.at(-1)} ms` : ""}
Unverified fixtures     ${scored.filter((s) => !s.fixture.verified).length} (expected values not yet checked by a person)`);
const tokens = scored.reduce((t, s) => ({ in: t.in + (s.result.usage?.prompt_tokens ?? 0), out: t.out + (s.result.usage?.completion_tokens ?? 0) }), { in: 0, out: 0 });
if (tokens.in) console.log(`Tokens                  ${tokens.in} in, ${tokens.out} out (${Math.round(tokens.out / scored.length)} out per photo)`);

const report = join(runDir, "report.html");
writeFileSync(report, renderReport(scored, sum, relative(runDir, FIXTURES_DIR)));
console.log(`\nReport: ${report}`);

const failUnder = option("fail-under");
if (failUnder && (100 * sum.valuesCorrect) / Math.max(1, sum.values) < Number(failUnder)) process.exit(1);

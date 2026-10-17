// Reads every ingredients box fixture (eval/box/) and scores the answers. See eval/README.md.
//
//   npm run eval:box                      the deployed Worker's /v1/ingredients-box/read
//   npm run eval:box -- --direct          straight to AI& with this checkout's prompt (needs AIAND_API_KEY)
//   npm run eval:box -- --direct --model google/gemma-4-31b-it --reasoning high
//   npm run eval:box -- --only curry-pouch,mizkan-vinegar
//   npm run eval:box -- --fail-under 95   exit 1 if fewer than 95% of ingredients and allergens are right

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { boxCompletionRequest, parseBoxCompletion, type ExtractedIngredientsBox } from "../src/ingredients.ts";
import { loadBoxFixtures, scoreBox, summariseBoxes, type BoxFixture } from "./box-lib.ts";
import { EVAL_DIR, FIXTURES_DIR, loadPhoto, pct } from "./lib.ts";

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(`--${name}`);
const option = (name: string) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : undefined; };

if (!process.env.AIAND_API_KEY) {
  try {
    const vars = readFileSync(join(EVAL_DIR, "../.dev.vars"), "utf8");
    process.env.AIAND_API_KEY = /^AIAND_API_KEY\s*=\s*"?([^"\n]+)"?/m.exec(vars)?.[1];
  } catch {}
}

function apiURL(): string {
  if (process.env.NUTRIFACTS_API_URL) return process.env.NUTRIFACTS_API_URL;
  const xcconfig = readFileSync(join(EVAL_DIR, "../../App/Config/NutriFacts.xcconfig"), "utf8");
  const url = xcconfig.split("\n").find((l) => l.startsWith("NUTRIFACTS_API_URL"))?.split("=")[1]?.trim().replace("$()", "");
  if (!url) throw new Error("Set NUTRIFACTS_API_URL.");
  return url;
}

const deployedModel = () => /"AIAND_MODEL":\s*"([^"]+)"/.exec(readFileSync(join(EVAL_DIR, "../wrangler.jsonc"), "utf8"))?.[1] ?? "";

interface Result { id: string; ms: number; box?: ExtractedIngredientsBox; error?: string }

async function read(fixture: BoxFixture, direct: boolean, model: string, reasoning?: string): Promise<Result> {
  const photo = loadPhoto(join(FIXTURES_DIR, fixture.photo));
  const started = Date.now();
  if (direct) {
    const res = await fetch("https://api.aiand.com/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${process.env.AIAND_API_KEY}` },
      body: JSON.stringify(boxCompletionRequest(model, photo.base64, photo.mimeType, reasoning)),
      signal: AbortSignal.timeout(300_000),
    });
    const body = await res.json().catch(() => null);
    const ms = Date.now() - started;
    if (!res.ok) return { id: fixture.id, ms, error: (body as { error?: { message?: string } })?.error?.message ?? `HTTP ${res.status}` };
    try { return { id: fixture.id, ms, box: parseBoxCompletion(body) }; } catch (e) { return { id: fixture.id, ms, error: (e as Error).message }; }
  }
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (process.env.NUTRIFACTS_APP_TOKEN) headers["X-App-Token"] = process.env.NUTRIFACTS_APP_TOKEN;
  const res = await fetch(`${apiURL()}/v1/ingredients-box/read`, {
    method: "POST", headers, signal: AbortSignal.timeout(120_000),
    body: JSON.stringify({ image: photo.base64, mimeType: photo.mimeType, ...(reasoning ? { reasoningEffort: reasoning } : {}) }),
  });
  const body = await res.json().catch(() => null);
  const ms = Date.now() - started;
  if (!res.ok) return { id: fixture.id, ms, error: (body as { error?: { message?: string } })?.error?.message ?? `HTTP ${res.status}` };
  return { id: fixture.id, ms, box: body as ExtractedIngredientsBox };
}

const direct = flag("direct");
if (direct && !process.env.AIAND_API_KEY) throw new Error("--direct needs AIAND_API_KEY, in your shell or in backend/.dev.vars.");
const model = option("model") ?? deployedModel();
const reasoning = option("reasoning");
const fixtures = loadBoxFixtures(option("only")?.split(","));
console.log(`Reading ${fixtures.length} ingredients boxes with ${direct ? `AI& ${model}, this checkout's prompt` : apiURL()}${reasoning ? ` (reasoning ${reasoning})` : ""}\n`);

// One at a time: the Worker allows 10 reads a minute, and there are only a few photos.
const results: Result[] = [];
for (const f of fixtures) {
  const r: Result = await read(f, direct, model, reasoning).catch((e: Error) => ({ id: f.id, ms: 0, error: e.message }));
  results.push(r);
  const s = scoreBox(f.expected, r.box);
  console.log(`${f.id}${f.verified ? "" : " (unverified)"}  ${r.error ? `✗ ${r.error}` : `${r.ms} ms${s.perfect ? "  perfect" : ""}`}`);
  for (const c of s.checks.filter((c) => c.verdict !== "ok")) console.log(`    ${c.field} ${c.verdict}: expected ${c.expected}, got ${c.actual}`);
  // Translations aren't scored: print them to read by eye.
  if (r.box?.boxFound) {
    console.log(`    → ${r.box.ingredients.map((i) => i.english + (i.isAdditive ? "*" : "")).join(", ")}`);
    console.log(`    → allergens: ${r.box.allergens.join(", ") || "none"} · ${r.box.category.english} · ${r.box.netContentsText}`);
  }
  if (!direct && f !== fixtures.at(-1)) await new Promise((r) => setTimeout(r, 6500));
}

const sum = summariseBoxes(fixtures.map((f, i) => scoreBox(f.expected, results[i].box)));
const [ingOk, ingN] = sum.ingredients, [alOk, alN] = sum.allergens;
console.log(`
Perfect boxes      ${sum.perfect}/${sum.fixtures}
Box found          ${pct(...sum.boxFound)}  (${sum.boxFound.join("/")})
Ingredients        ${pct(ingOk, ingN)}  (${ingOk}/${ingN}), ${sum.inventedIngredients} invented
Allergens          ${pct(alOk, alN)}  (${alOk}/${alN}), ${sum.inventedAllergens} invented
Net contents       ${pct(...sum.netContents)}  (${sum.netContents.join("/")})
Food type, date, additives  ${pct(...sum.other)}  (${sum.other.join("/")})
Average time       ${Math.round(results.reduce((t, r) => t + r.ms, 0) / Math.max(1, results.length))} ms`);

const runDir = join(EVAL_DIR, "runs", `box-${new Date().toISOString().slice(0, 19).replaceAll(":", "-")}${direct ? `-${model.replace(/\W+/g, "_")}` : ""}`);
mkdirSync(runDir, { recursive: true });
writeFileSync(join(runDir, "results.json"), JSON.stringify({ direct, model, reasoning, at: new Date().toISOString(), results, summary: sum }, null, 2));
console.log(`\nSaved ${join(runDir, "results.json")}`);

const failUnder = option("fail-under");
if (failUnder && (100 * (ingOk + alOk)) / Math.max(1, ingN + alN) < Number(failUnder)) process.exit(1);

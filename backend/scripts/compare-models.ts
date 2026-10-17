// Sends the same label photos to every vision model on your AI& account, using the Worker's own
// prompt and schema, and prints what each model read, how long it took and roughly what it cost.
//
//   AIAND_API_KEY=sk-… npm run compare -- photo1.jpg photo2.heic
//   AIAND_API_KEY=sk-… npm run compare -- --models qwen/qwen3.8-27b,google/gemma-4-31b-it photo.jpg
//   AIAND_API_KEY=sk-… npm run compare -- --models qwen/qwen3.8-27b --effort none,low,xhigh photo.jpg
//
// --effort runs each model at each listed reasoning level it supports. Without it, the model's own default is used.
//
// Runs on your Mac and calls AI& directly; the Worker isn't involved. HEIC photos are converted
// to JPEG with macOS's `sips`, since AI& takes JPEG, PNG and WebP.

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, extname, join } from "node:path";
import { completionRequest, parseCompletion, type ExtractedLabel } from "../src/label.ts";

const BASE = "https://api.aiand.com/v1";
const key = process.env.AIAND_API_KEY;
if (!key) throw new Error("Set AIAND_API_KEY in your shell first.");

const args = process.argv.slice(2);
const modelsFlag = args.indexOf("--models");
const chosen = modelsFlag >= 0 ? args.splice(modelsFlag, 2)[1].split(",") : undefined;
const effortFlag = args.indexOf("--effort");
const efforts = effortFlag >= 0 ? args.splice(effortFlag, 2)[1].split(",") : [undefined];
const photos = args;
if (photos.length === 0) throw new Error("Pass one or more photo paths.");

interface Model { id: string; capabilities?: string[]; reasoning_efforts?: string[]; input_per_1m?: string; output_per_1m?: string; currency?: string }

const list = (await (await fetch(`${BASE}/models`, { headers: { Authorization: `Bearer ${key}` } })).json()) as { data: Model[] };
const models = list.data.filter((m) => (chosen ? chosen.includes(m.id) : m.capabilities?.includes("vision")));
if (models.length === 0) throw new Error("No matching vision models on this account.");

const scratch = mkdtempSync(join(tmpdir(), "nutrifacts-compare-"));
function load(path: string): { base64: string; mime: string } {
  const ext = extname(path).toLowerCase();
  if (ext === ".heic" || ext === ".heif") {
    const out = join(scratch, basename(path, ext) + ".jpg");
    execFileSync("sips", ["-s", "format", "jpeg", "-Z", "2048", path, "--out", out], { stdio: "ignore" });
    return { base64: readFileSync(out).toString("base64"), mime: "image/jpeg" };
  }
  const mime = ext === ".png" ? "image/png" : ext === ".webp" ? "image/webp" : "image/jpeg";
  return { base64: readFileSync(path).toString("base64"), mime };
}

function summary(l: ExtractedLabel): string {
  if (!l.panelFound) return "no panel found";
  const v = (n: string) => l.lines.find((x) => x.nutrient === n);
  const show = (n: string) => { const x = v(n); return x ? `${x.minValue}${x.unit}` : "—"; };
  const contents = l.netContentsAmount > 0 ? `${l.netContentsAmount}${l.netContentsUnit}` + (l.netContentsCount ? `÷${l.netContentsCount}` : "") : "—";
  return `basis "${l.basisText}" (${l.basisAmount || "?"}${l.basisAmount ? l.basisUnit : ""}) · 内容量 ${contents} · ` +
    `${l.lines.length} lines · kcal ${show("energy")} P ${show("protein")} F ${show("fat")} C ${show("carbohydrate")} 塩 ${show("salt")}` +
    (l.isEstimate ? " · 推定値" : "");
}

for (const photo of photos) {
  const image = load(photo);
  console.log(`\n${basename(photo)}`);
  for (const m of models) {
    for (const effort of efforts) {
      if (effort && !m.reasoning_efforts?.includes(effort)) continue;
      const started = Date.now();
      const res = await fetch(`${BASE}/chat/completions`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
        body: JSON.stringify(completionRequest(m.id, image.base64, image.mime, effort)),
      });
      const ms = Date.now() - started;
      const body = (await res.json().catch(() => null)) as {
        usage?: { prompt_tokens?: number; completion_tokens?: number; completion_tokens_details?: { reasoning_tokens?: number } };
        error?: { message?: string };
      } | null;
      let line: string;
      if (!res.ok) {
        line = `HTTP ${res.status}: ${body?.error?.message ?? "error"}`;
      } else {
        try { line = summary(parseCompletion(body)); } catch (e) { line = `unreadable answer (${(e as Error).message})`; }
      }
      const u = body?.usage;
      const cost = u && m.input_per_1m && m.output_per_1m
        ? ((u.prompt_tokens ?? 0) * Number(m.input_per_1m) + (u.completion_tokens ?? 0) * Number(m.output_per_1m)) / 1e6
        : undefined;
      const applied = res.headers.get("X-Reasoning-Effort") ?? effort ?? "default";
      const thinking = u?.completion_tokens_details?.reasoning_tokens;
      const extras = [`effort ${applied}`, thinking !== undefined ? `${thinking} reasoning tokens` : "",
        cost === undefined ? "" : `${cost.toFixed(5)} ${m.currency ?? ""}`].filter(Boolean).join(" · ");
      console.log(`  ${m.id.padEnd(34)} ${String(ms).padStart(6)} ms · ${extras}\n    ${line}`);
    }
  }
}

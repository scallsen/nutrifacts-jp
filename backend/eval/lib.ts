// Fixtures and scoring for the label-reading eval. See eval/README.md.

import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, extname, join } from "node:path";
import { NUTRIENTS, type ExtractedLabel, type ExtractedLine } from "../src/label.ts";

export const EVAL_DIR = import.meta.dirname;
export const FIXTURES_DIR = join(EVAL_DIR, "fixtures");

export interface Fixture {
  id: string;
  photo: string;
  notes?: string;
  source?: { title?: string | null; url?: string; page?: string; license?: string; author?: string };
  /** The correct reading. null until a reference has been made. */
  expected: ExtractedLabel | null;
  /** How `expected` was made, e.g. two independent Claude passes that agreed. */
  reference?: { by: string; at: string; agreement?: "agreed" | "resolved" | "single" ; disagreements?: string[] };
  /** True once a person has checked `expected` against the photo. */
  verified: boolean;
  /** For your own photos (eval:import): what the app read at the time, to compare with `expected`. */
  appReading?: unknown;
}

export function loadFixtures(only?: string[]): Fixture[] {
  return readdirSync(FIXTURES_DIR)
    .filter((f) => f.endsWith(".json"))
    .map((f) => ({ id: basename(f, ".json"), ...JSON.parse(readFileSync(join(FIXTURES_DIR, f), "utf8")) }) as Fixture)
    .filter((f) => !only || only.includes(f.id))
    .sort((a, b) => a.id.localeCompare(b.id));
}

export function saveFixture(fixture: Fixture): void {
  const { id, ...rest } = fixture;
  writeFileSync(join(FIXTURES_DIR, `${id}.json`), JSON.stringify(rest, null, 2) + "\n");
}

let scratch: string | undefined;
/** The photo as the app would send it: JPEG, PNG or WebP, at most 2048 px on the long side. HEIC and large files go through macOS `sips`. */
export function loadPhoto(path: string): { base64: string; mimeType: string } {
  const ext = extname(path).toLowerCase();
  const native = ext === ".jpg" || ext === ".jpeg" || ext === ".png" || ext === ".webp";
  if (!native || statSync(path).size > 4 * 1024 * 1024) {
    scratch ??= mkdtempSync(join(tmpdir(), "nutrifacts-eval-"));
    const out = join(scratch, basename(path, ext) + ".jpg");
    execFileSync("sips", ["-s", "format", "jpeg", "-Z", "2048", path, "--out", out], { stdio: "ignore" });
    return { base64: readFileSync(out).toString("base64"), mimeType: "image/jpeg" };
  }
  const mimeType = ext === ".png" ? "image/png" : ext === ".webp" ? "image/webp" : "image/jpeg";
  return { base64: readFileSync(path).toString("base64"), mimeType };
}

// Scoring ---------------------------------------------------------------------------------------

/** Nutrients that count towards the score. `other` lines are shown but never scored. */
export const SCORED = NUTRIENTS.filter((n) => n !== "other");

export type Verdict = "ok" | "wrong" | "missing" | "invented";

export interface Check {
  /** What was checked: a nutrient (`salt`), or a field (`panelFound`, `basis`, `estimate`, `netContents`). */
  field: string;
  expected: string;
  actual: string;
  verdict: Verdict;
}

export interface Score {
  checks: Check[];
  /** Every check passed. */
  perfect: boolean;
}

export function normaliseUnit(unit: string): string {
  const u = unit.normalize("NFKC").trim();
  if (/^(µg|μg|ug|mcg)$/i.test(u)) return "µg";
  if (/^(ml|mℓ)$/i.test(u)) return "ml";
  return u.toLowerCase().replace("kcal", "kcal");
}

const same = (a: number, b: number) => Math.abs(a - b) < 1e-6;

export function formatLine(l: Pick<ExtractedLine, "minValue" | "maxValue" | "unit"> | undefined): string {
  if (!l) return "—";
  return (same(l.minValue, l.maxValue) ? `${l.minValue}` : `${l.minValue}〜${l.maxValue}`) + normaliseUnit(l.unit);
}

function formatBasis(l: ExtractedLabel): string {
  return l.basisAmount > 0 ? `${l.basisAmount}${l.basisUnit}` : "none";
}

function formatContents(l: ExtractedLabel): string {
  if (!(l.netContentsAmount > 0)) return l.netContentsCount > 0 ? `${l.netContentsCount}個` : "none";
  return `${l.netContentsAmount}${l.netContentsUnit}` + (l.netContentsCount > 0 ? ` ×${l.netContentsCount}` : "");
}

export function score(expected: ExtractedLabel, actual: ExtractedLabel | undefined): Score {
  const checks: Check[] = [];
  const check = (field: string, e: string, a: string, verdict: Verdict = e === a ? "ok" : "wrong") =>
    checks.push({ field, expected: e, actual: a, verdict });

  check("panelFound", String(expected.panelFound), actual ? String(actual.panelFound) : "no answer");
  if (!expected.panelFound) return { checks, perfect: checks.every((c) => c.verdict === "ok") };

  const got = actual?.panelFound ? actual : undefined;
  check("basis", formatBasis(expected), got ? formatBasis(got) : "—");
  check("estimate", String(expected.isEstimate), got ? String(got.isEstimate) : "—");
  check("netContents", formatContents(expected), got ? formatContents(got) : "—");

  // Pair each expected line with a returned line for the same nutrient, preferring an exact match
  // (so 熱量 in kJ and in kcal pair up correctly).
  const scored = (l: ExtractedLine) => (SCORED as readonly string[]).includes(l.nutrient);
  const remaining = (got?.lines ?? []).filter(scored);
  const matches = (e: ExtractedLine, a: ExtractedLine) =>
    a.nutrient === e.nutrient && normaliseUnit(a.unit) === normaliseUnit(e.unit) &&
    same(a.minValue, e.minValue) && same(a.maxValue, e.maxValue);
  for (const e of expected.lines.filter(scored)) {
    let i = remaining.findIndex((a) => matches(e, a));
    if (i < 0) i = remaining.findIndex((a) => a.nutrient === e.nutrient);
    if (i < 0) {
      check(e.nutrient, formatLine(e), "—", "missing");
      continue;
    }
    const [a] = remaining.splice(i, 1);
    check(e.nutrient, formatLine(e), formatLine(a), matches(e, a) ? "ok" : "wrong");
  }
  // Anything left is a line that isn't on the label: the worst mistake, since the app would show a value that isn't printed.
  for (const a of remaining) check(a.nutrient, "—", formatLine(a), "invented");

  return { checks, perfect: checks.every((c) => c.verdict === "ok") };
}

export interface Summary {
  fixtures: number;
  perfect: number;
  panelChecks: number;
  panelCorrect: number;
  values: number;
  valuesCorrect: number;
  invented: number;
  basisChecks: number;
  basisCorrect: number;
}

export function summarise(scores: Score[]): Summary {
  const all = scores.flatMap((s) => s.checks);
  const nutrient = (c: Check) => (SCORED as readonly string[]).includes(c.field);
  const values = all.filter((c) => nutrient(c) && c.verdict !== "invented");
  const field = (name: string) => all.filter((c) => c.field === name);
  return {
    fixtures: scores.length,
    perfect: scores.filter((s) => s.perfect).length,
    panelChecks: field("panelFound").length,
    panelCorrect: field("panelFound").filter((c) => c.verdict === "ok").length,
    values: values.length,
    valuesCorrect: values.filter((c) => c.verdict === "ok").length,
    invented: all.filter((c) => c.verdict === "invented").length,
    basisChecks: field("basis").length,
    basisCorrect: field("basis").filter((c) => c.verdict === "ok").length,
  };
}

export const pct = (n: number, d: number) => (d === 0 ? "—" : `${((100 * n) / d).toFixed(1)}%`);

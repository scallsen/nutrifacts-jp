// Fixtures and scoring for the ingredients box eval (npm run eval:box). See eval/README.md.

import { readdirSync, readFileSync } from "node:fs";
import { basename, join } from "node:path";
import type { ExtractedIngredientsBox } from "../src/ingredients.ts";
import { EVAL_DIR, type Check, type Verdict } from "./lib.ts";

export const BOX_DIR = join(EVAL_DIR, "box");

export interface BoxFixture {
  id: string;
  /** A photo in eval/fixtures/, shared with the panel eval. */
  photo: string;
  notes?: string;
  expected: ExtractedIngredientsBox;
  reference?: { by: string; at: string };
  verified: boolean;
}

export function loadBoxFixtures(only?: string[]): BoxFixture[] {
  return readdirSync(BOX_DIR)
    .filter((f) => f.endsWith(".json"))
    .map((f) => ({ id: basename(f, ".json"), ...JSON.parse(readFileSync(join(BOX_DIR, f), "utf8")) }) as BoxFixture)
    .filter((f) => !only || only.includes(f.id))
    .sort((a, b) => a.id.localeCompare(b.id));
}

/** 豚肉（国産）, 豚肉 (国産) and 豚肉(国産) are the same text. */
export function normaliseText(text: string): string {
  return text.normalize("NFKC").replace(/\s/g, "").replace(/[、,]$/, "");
}

/** The same allergen, however the pack spells it: 乳成分 and 乳, 落花生 and ピーナッツ. */
export function canonicalAllergen(name: string): string {
  const n = normaliseText(name);
  if (/^(乳|乳成分|乳製品)$/.test(n)) return "乳";
  if (/^(落花生|ピーナッツ)$/.test(n)) return "落花生";
  if (/^(卵|鶏卵|玉子)$/.test(n)) return "卵";
  return n;
}

function formatContents(b: ExtractedIngredientsBox): string {
  if (b.netContentsPrintedElsewhere) return "printed elsewhere";
  const amount = b.netContentsAmount > 0 ? `${b.netContentsAmount}${b.netContentsUnit}` : "";
  const count = b.netContentsCount > 0 ? `${b.netContentsCount}個` : "";
  return [amount, count].filter(Boolean).join(" ×") || "none";
}

export interface BoxScore {
  checks: Check[];
  perfect: boolean;
}

/**
 * Scores a reading field by field. Ingredients pair up by their printed Japanese, in any order.
 * Translations aren't scored; the runner prints them to read by eye. Additive flags are only scored
 * on boxes that mark additives (a ／ or a 添加物 line), since older boxes don't say which they are.
 */
export function scoreBox(expected: ExtractedIngredientsBox, actual: ExtractedIngredientsBox | undefined): BoxScore {
  const checks: Check[] = [];
  const check = (field: string, e: string, a: string, verdict: Verdict = e === a ? "ok" : "wrong") =>
    checks.push({ field, expected: e, actual: a, verdict });

  check("boxFound", String(expected.boxFound), actual ? String(actual.boxFound) : "no answer");
  if (!expected.boxFound) return { checks, perfect: checks.every((c) => c.verdict === "ok") };
  const got = actual?.boxFound ? actual : undefined;

  check("category", normaliseText(expected.category.japanese), got ? normaliseText(got.category.japanese) : "—");
  check("netContents", formatContents(expected), got ? formatContents(got) : "—");
  if (expected.date.japanese) check("useBy", String(expected.isUseBy), got ? String(got.isUseBy) : "—");

  const marksAdditives = expected.ingredients.some((i) => i.isAdditive);
  const remaining = [...(got?.ingredients ?? [])];
  for (const e of expected.ingredients) {
    const i = remaining.findIndex((a) => normaliseText(a.japanese) === normaliseText(e.japanese));
    if (i < 0) {
      check("ingredient", e.japanese, "—", "missing");
      continue;
    }
    const [a] = remaining.splice(i, 1);
    check("ingredient", e.japanese, a.japanese, "ok");
    if (marksAdditives) check("additive", `${e.japanese} ${e.isAdditive}`, `${e.japanese} ${a.isAdditive}`);
  }
  for (const a of remaining) check("ingredient", "—", a.japanese, "invented");

  // A missed allergen is the worst mistake here: the app would leave it off the warning.
  const left = (got?.allergens ?? []).map(canonicalAllergen);
  for (const e of expected.allergens) {
    const i = left.indexOf(canonicalAllergen(e));
    if (i < 0) check("allergen", e, "—", "missing");
    else check("allergen", e, left.splice(i, 1)[0], "ok");
  }
  for (const a of left) check("allergen", "—", a, "invented");

  return { checks, perfect: checks.every((c) => c.verdict === "ok") };
}

export interface BoxSummary {
  fixtures: number;
  perfect: number;
  boxFound: [number, number];
  ingredients: [number, number];
  inventedIngredients: number;
  allergens: [number, number];
  inventedAllergens: number;
  netContents: [number, number];
  other: [number, number];
}

export function summariseBoxes(scores: BoxScore[]): BoxSummary {
  const all = scores.flatMap((s) => s.checks);
  const tally = (field: string): [number, number] => {
    const c = all.filter((x) => x.field === field && x.verdict !== "invented");
    return [c.filter((x) => x.verdict === "ok").length, c.length];
  };
  const others = all.filter((c) => ["category", "useBy", "additive"].includes(c.field));
  return {
    fixtures: scores.length,
    perfect: scores.filter((s) => s.perfect).length,
    boxFound: tally("boxFound"),
    ingredients: tally("ingredient"),
    inventedIngredients: all.filter((c) => c.field === "ingredient" && c.verdict === "invented").length,
    allergens: tally("allergen"),
    inventedAllergens: all.filter((c) => c.field === "allergen" && c.verdict === "invented").length,
    netContents: tally("netContents"),
    other: [others.filter((c) => c.verdict === "ok").length, others.length],
  };
}

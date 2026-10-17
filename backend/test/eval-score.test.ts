import { strict as assert } from "node:assert";
import { test } from "node:test";
import type { ExtractedLabel, ExtractedLine } from "../src/label.ts";
import { score, summarise } from "../eval/lib.ts";

const line = (nutrient: ExtractedLine["nutrient"], min: number, unit = "g", max = min): ExtractedLine =>
  ({ nutrient, printedName: nutrient, minValue: min, maxValue: max, unit });

const label = (lines: ExtractedLine[], overrides: Partial<ExtractedLabel> = {}): ExtractedLabel => ({
  panelFound: true, productName: "", basisText: "100g当たり", basisAmount: 100, basisUnit: "g",
  netContentsAmount: 0, netContentsUnit: "none", netContentsCount: 0, isEstimate: false, lines, ...overrides,
});

const verdicts = (e: ExtractedLabel, a?: ExtractedLabel) =>
  score(e, a).checks.filter((c) => c.verdict !== "ok").map((c) => `${c.field}:${c.verdict}`);

test("an identical reading is perfect", () => {
  const l = label([line("energy", 315, "kcal"), line("carbohydrate", 0, "g", 1.6), line("other", 93, "mg")]);
  assert.ok(score(l, structuredClone(l)).perfect);
});

test("a wrong value, a missing line and an invented line are told apart", () => {
  const expected = label([line("energy", 315, "kcal"), line("protein", 53.5), line("salt", 4.3)]);
  const actual = label([line("energy", 315, "kcal"), line("protein", 5.35), line("sugars", 0)]);
  assert.deepEqual(verdicts(expected, actual), ["protein:wrong", "salt:missing", "sugars:invented"]);
});

test("a range must match at both ends", () => {
  assert.deepEqual(verdicts(label([line("carbohydrate", 0, "g", 1.6)]), label([line("carbohydrate", 1.6)])), ["carbohydrate:wrong"]);
});

test("other lines are never scored", () => {
  assert.ok(score(label([line("other", 38, "mg")]), label([])).perfect);
});

test("units are compared after normalising µg spellings", () => {
  assert.ok(score(label([line("energy", 5, "μg")]), label([line("energy", 5, "ug")])).perfect);
});

test("no net contents counts the same whatever unit comes with the 0", () => {
  assert.ok(score(label([]), label([], { netContentsUnit: "g" })).perfect);
});

test("a missing panel only checks panelFound", () => {
  const none = label([], { panelFound: false });
  assert.ok(score(none, label([], { panelFound: false, basisAmount: 7 })).perfect);
  assert.deepEqual(verdicts(none, label([line("energy", 1, "kcal")])), ["panelFound:wrong"]);
});

test("no answer from the service fails every value", () => {
  const s = score(label([line("energy", 315, "kcal")]), undefined);
  assert.equal(s.perfect, false);
  const sum = summarise([s]);
  assert.equal(sum.values, 1);
  assert.equal(sum.valuesCorrect, 0);
});

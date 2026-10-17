import { strict as assert } from "node:assert";
import { afterEach, test } from "node:test";
import worker, { type Env } from "../src/index.ts";
import { boxCompletionRequest, parseBoxCompletion, type ExtractedIngredientsBox } from "../src/ingredients.ts";
import { loadBoxFixtures, scoreBox } from "../eval/box-lib.ts";

const text = (japanese = "", english = "") => ({ japanese, english });
const box: ExtractedIngredientsBox = {
  boxFound: true, category: text("清涼飲料水", "soft drink"),
  ingredients: [
    { japanese: "砂糖", english: "sugar", isAdditive: false },
    { japanese: "香料", english: "flavouring", isAdditive: true },
  ],
  allergens: ["乳成分"], netContentsText: "500ml", netContentsAmount: 500, netContentsUnit: "ml", netContentsCount: 0,
  netContentsPrintedElsewhere: false, date: text("キャップに記載", "printed on the cap"), isUseBy: false,
  storage: text(), maker: "株式会社サンプル", countryOfOrigin: text(),
};
const completion = (b: unknown) => ({ choices: [{ message: { content: JSON.stringify(b) } }] });

const env: Env = {
  AIAND_API_KEY: "sk-test", AIAND_MODEL: "vision-model", AIAND_BASE_URL: "https://aiand.test/v1",
  READ_LIMITER: { limit: async () => ({ success: true }) } as unknown as RateLimit,
};
const realFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = realFetch; });

test("the box request has its own prompt and a strict schema", () => {
  const req = boxCompletionRequest("m", "QUJD", "image/jpeg");
  assert.match(req.messages[0].content as string, /一括表示/);
  assert.equal(req.response_format.json_schema.name, "ingredients_box");
  assert.equal(req.response_format.json_schema.strict, true);
});

test("reads a box through its own route", async () => {
  let sent: { messages: { content: unknown }[] } | undefined;
  globalThis.fetch = (async (input: RequestInfo, init?: RequestInit) => {
    const req = new Request(input, init);
    if (req.url.endsWith("/models")) return new Response(JSON.stringify({ data: [] }));
    sent = await req.json();
    return new Response(JSON.stringify(completion(box)));
  }) as typeof fetch;
  const res = await worker.fetch(new Request("https://api.example/v1/ingredients-box/read", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ image: "QUJD" }),
  }), env);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), box);
  assert.match(sent!.messages[0].content as string, /一括表示/);
});

test("the allergen statement isn't an ingredient", () => {
  const parsed = parseBoxCompletion(completion({ ...box, ingredients: [...box.ingredients,
    { japanese: "（一部に乳成分・大豆を含む）", english: "contains milk and soy", isAdditive: false },
    { japanese: "(原材料の一部にりんごを含む)", english: "", isAdditive: false }] }));
  assert.deepEqual(parsed.ingredients.map((i) => i.japanese), ["砂糖", "香料"]);
});

test("no box means an empty reading", () => {
  const parsed = parseBoxCompletion(completion({ ...box, boxFound: false }));
  assert.deepEqual([parsed.ingredients, parsed.allergens, parsed.netContentsAmount, parsed.maker], [[], [], 0, ""]);
});

test("scoring pairs ingredients by their Japanese and spellings of the same allergen", () => {
  const actual = { ...box, allergens: ["乳"], ingredients: [{ ...box.ingredients[1] }, { japanese: "砂 糖", english: "Sugar", isAdditive: false }] };
  assert.ok(scoreBox(box, actual).perfect);
});

test("scoring flags a missed allergen, a missing ingredient and an invented one", () => {
  const actual = { ...box, allergens: ["大豆"], ingredients: [box.ingredients[0], { japanese: "食塩", english: "salt", isAdditive: false }] };
  const bad = scoreBox(box, actual).checks.filter((c) => c.verdict !== "ok").map((c) => `${c.field}:${c.verdict}`);
  assert.deepEqual(bad, ["ingredient:missing", "ingredient:invented", "allergen:missing", "allergen:invented"]);
});

test("every box fixture scores perfect against itself", () => {
  const fixtures = loadBoxFixtures();
  assert.ok(fixtures.length >= 6);
  for (const f of fixtures) assert.ok(scoreBox(f.expected, structuredClone(f.expected)).perfect, f.id);
});

import { strict as assert } from "node:assert";
import { afterEach, beforeEach, test } from "node:test";
import worker, { pickEffort, resetEffortsCache, type Env } from "../src/index.ts";
import { completionRequest, parseCompletion } from "../src/label.ts";

const label = {
  panelFound: true, productName: "", basisText: "1個当たり", basisAmount: 0, basisUnit: "ml",
  netContentsAmount: 350, netContentsUnit: "ml", netContentsCount: 0, isEstimate: false,
  lines: [{ nutrient: "energy", printedName: "熱量", minValue: 140, maxValue: 140, unit: "kcal" }],
};
const completion = {
  choices: [{ message: { content: JSON.stringify(label) } }],
  usage: { prompt_tokens: 2400, completion_tokens: 300, completion_tokens_details: { reasoning_tokens: 120 } },
};
const models = { data: [{ id: "vision-model", reasoning_efforts: ["none", "low", "medium", "xhigh"] }] };

function env(overrides: Partial<Env> = {}): Env {
  return {
    AIAND_API_KEY: "sk-test", AIAND_MODEL: "vision-model", AIAND_REASONING_EFFORT: "low", AIAND_BASE_URL: "https://aiand.test/v1",
    READ_LIMITER: { limit: async () => ({ success: true }) } as unknown as RateLimit,
    ...overrides,
  };
}

function read(body: unknown, headers: Record<string, string> = {}) {
  return new Request("https://api.example/v1/nutrition-label/read", {
    method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body),
  });
}

/** A fake AI&: answers the model list and chat completions, and records completion requests. */
let sent: Request[] = [];
function fakeAIAnd(chat: () => Response = () => new Response(JSON.stringify(completion), { headers: { "X-Reasoning-Effort": "low" } })) {
  globalThis.fetch = (async (input: RequestInfo, init?: RequestInit) => {
    const req = new Request(input, init);
    if (req.url.endsWith("/models")) return new Response(JSON.stringify(models));
    sent.push(req);
    return chat();
  }) as typeof fetch;
}
async function sentBody() { return (await sent.at(-1)!.clone().json()) as { reasoning_effort?: string }; }

const realFetch = globalThis.fetch;
beforeEach(() => { sent = []; resetEffortsCache(); });
afterEach(() => { globalThis.fetch = realFetch; });

test("request sends the photo inline with a strict schema", () => {
  const req = completionRequest("m", "QUJD", "image/jpeg", "low");
  assert.equal(req.model, "m");
  assert.equal(req.reasoning_effort, "low");
  assert.equal(req.response_format.json_schema.strict, true);
  const parts = req.messages[1].content as { type: string; image_url?: { url: string } }[];
  assert.equal(parts[1].image_url?.url, "data:image/jpeg;base64,QUJD");
  assert.equal("reasoning_effort" in completionRequest("m", "QUJD", "image/jpeg"), false);
});

const parse = (l: unknown) => parseCompletion({ choices: [{ message: { content: JSON.stringify(l) } }] });
const printed = (printedName: string, nutrient = "other") => ({ nutrient, printedName, minValue: 1, maxValue: 1, unit: "g" });

test("parses the label out of a completion", () => {
  assert.deepEqual(parse(label), label);
  assert.throws(() => parseCompletion({ choices: [] }));
});

test("the printed name decides the nutrient, whatever the model chose", () => {
  const lines = parse({ ...label, lines: [
    printed("糖質", "sugars"), printed("ー糖　類", "netCarbs"), printed("カリウム", "sodium"),
    printed("(食塩相当量)", "other"), printed("スクロース", "sugars"), printed("熱量", "caffeine"),
  ] }).lines;
  assert.deepEqual(lines.map((l) => l.nutrient), ["netCarbs", "sugars", "other", "salt", "other", "energy"]);
});

test("a panel without any Japanese line names isn't a Japanese panel", () => {
  const parsed = parse({ ...label, lines: [printed("Energy", "energy"), printed("Sugars", "sugars")] });
  assert.equal(parsed.panelFound, false);
  assert.deepEqual(parsed.lines, []);
});

test("reads a label through AI& with the key on the server and the default reasoning level", async () => {
  fakeAIAnd();
  const res = await worker.fetch(read({ image: "QUJD", mimeType: "image/jpeg" }), env());
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), label);
  assert.equal(res.headers.get("X-Reasoning-Effort"), "low");
  assert.match(res.headers.get("Server-Timing") ?? "", /^aiand;dur=\d+, total;dur=\d+$/);
  assert.equal(res.headers.get("X-AIAnd-Usage"), "promptTokens=2400; completionTokens=300; reasoningTokens=120");
  assert.equal(sent[0].url, "https://aiand.test/v1/chat/completions");
  assert.equal(sent[0].headers.get("Authorization"), "Bearer sk-test");
  assert.equal((await sentBody()).reasoning_effort, "low");
});

test("uses the app's reasoning level when the model offers it", async () => {
  fakeAIAnd();
  await worker.fetch(read({ image: "QUJD", reasoningEffort: "xhigh" }), env());
  assert.equal((await sentBody()).reasoning_effort, "xhigh");
});

test("falls back to the default for a level the model doesn't offer", async () => {
  fakeAIAnd();
  await worker.fetch(read({ image: "QUJD", reasoningEffort: "max" }), env());
  assert.equal((await sentBody()).reasoning_effort, "low");
  // A default the model doesn't offer either: send none and let AI& use the model's own.
  assert.equal(pickEffort(env({ AIAND_REASONING_EFFORT: "max" }), ["none", "high"]), undefined);
});

test("config lists the model's reasoning levels and the default", async () => {
  fakeAIAnd();
  const res = await worker.fetch(new Request("https://api.example/v1/config"), env());
  assert.deepEqual(await res.json(), {
    model: "vision-model", reasoningEfforts: ["none", "low", "medium", "xhigh"], defaultReasoningEffort: "low",
  });
});

test("requires the app token when one is set", async () => {
  assert.equal((await worker.fetch(read({ image: "QUJD" }), env({ APP_TOKEN: "secret" }))).status, 401);
  assert.equal((await worker.fetch(new Request("https://api.example/v1/config"), env({ APP_TOKEN: "secret" }))).status, 401);
});

test("rate limits per client", async () => {
  const limited = env({ READ_LIMITER: { limit: async () => ({ success: false }) } as unknown as RateLimit });
  assert.equal((await worker.fetch(read({ image: "QUJD" }), limited)).status, 429);
});

test("hides AI& account problems from the client", async () => {
  fakeAIAnd(() => new Response(JSON.stringify({ error: { message: "insufficient credits" } }), { status: 402 }));
  const res = await worker.fetch(read({ image: "QUJD" }), env());
  assert.equal(res.status, 503);
  assert.doesNotMatch(JSON.stringify(await res.json()), /credit/);
});

test("only serves its own endpoints", async () => {
  assert.equal((await worker.fetch(new Request("https://api.example/v1/chat/completions", { method: "POST" }), env())).status, 404);
  assert.equal((await worker.fetch(new Request("https://api.example/v1/nutrition-label/read"), env())).status, 405);
});

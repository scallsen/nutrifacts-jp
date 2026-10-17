import { strict as assert } from "node:assert";
import { afterEach, test } from "node:test";
import worker, { type Env } from "../src/index.ts";
import { completionRequest, parseCompletion } from "../src/label.ts";

const label = {
  panelFound: true, productName: "", basisText: "1個当たり", basisAmount: 0, basisUnit: "ml",
  netContentsAmount: 350, netContentsUnit: "ml", netContentsCount: 0, isEstimate: false,
  lines: [{ nutrient: "energy", printedName: "熱量", minValue: 140, maxValue: 140, unit: "kcal" }],
};
const completion = { choices: [{ message: { content: JSON.stringify(label) } }] };

function env(overrides: Partial<Env> = {}): Env {
  return {
    AIAND_API_KEY: "sk-test", AIAND_MODEL: "vision-model", AIAND_BASE_URL: "https://aiand.test/v1",
    READ_LIMITER: { limit: async () => ({ success: true }) } as unknown as RateLimit,
    ...overrides,
  };
}

function read(body: unknown, headers: Record<string, string> = {}) {
  return new Request("https://api.example/v1/nutrition-label/read", {
    method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body),
  });
}

const realFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = realFetch; });

test("request sends the photo inline with a strict schema", () => {
  const req = completionRequest("m", "QUJD", "image/jpeg");
  assert.equal(req.model, "m");
  assert.equal(req.response_format.json_schema.strict, true);
  const parts = req.messages[1].content as { type: string; image_url?: { url: string } }[];
  assert.equal(parts[1].image_url?.url, "data:image/jpeg;base64,QUJD");
});

test("parses the label out of a completion and drops unknown nutrients", () => {
  const odd = { ...label, lines: [...label.lines, { ...label.lines[0], nutrient: "caffeine" }] };
  const parsed = parseCompletion({ choices: [{ message: { content: JSON.stringify(odd) } }] });
  assert.equal(parsed.lines.length, 1);
  assert.throws(() => parseCompletion({ choices: [] }));
});

test("reads a label through AI& with the key on the server", async () => {
  let sent: Request | undefined;
  globalThis.fetch = (async (input: RequestInfo, init?: RequestInit) => {
    sent = new Request(input, init);
    return new Response(JSON.stringify(completion));
  }) as typeof fetch;
  const res = await worker.fetch(read({ image: "QUJD", mimeType: "image/jpeg" }), env());
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), label);
  assert.equal(sent?.url, "https://aiand.test/v1/chat/completions");
  assert.equal(sent?.headers.get("Authorization"), "Bearer sk-test");
});

test("requires the app token when one is set", async () => {
  const res = await worker.fetch(read({ image: "QUJD" }), env({ APP_TOKEN: "secret" }));
  assert.equal(res.status, 401);
});

test("rate limits per client", async () => {
  const limited = env({ READ_LIMITER: { limit: async () => ({ success: false }) } as unknown as RateLimit });
  assert.equal((await worker.fetch(read({ image: "QUJD" }), limited)).status, 429);
});

test("hides AI& account problems from the client", async () => {
  globalThis.fetch = (async () => new Response(JSON.stringify({ error: { message: "insufficient credits" } }), { status: 402 })) as typeof fetch;
  const res = await worker.fetch(read({ image: "QUJD" }), env());
  assert.equal(res.status, 503);
  assert.doesNotMatch(JSON.stringify(await res.json()), /credit/);
});

test("only serves the read endpoint", async () => {
  assert.equal((await worker.fetch(new Request("https://api.example/v1/chat/completions", { method: "POST" }), env())).status, 404);
  assert.equal((await worker.fetch(new Request("https://api.example/v1/nutrition-label/read"), env())).status, 405);
});

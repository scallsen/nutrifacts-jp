// Makes the expected reading for new fixtures with Claude Opus 5.5, the reference model.
// Reads each photo twice, independently. Where the two readings agree, that's the expected
// reading; where they don't, it keeps the first and lists the differences for a person to settle
// with `npm run eval:review`. Either way the fixture stays unverified until a person checks it.
//
//   ANTHROPIC_API_KEY=sk-ant-… npm run eval:reference                 fixtures without an expected reading
//   ANTHROPIC_API_KEY=sk-ant-… npm run eval:reference -- --only butter-100g --force
//
// Add a fixture by dropping a photo into eval/fixtures/ (JPEG, PNG, WebP or HEIC). The script
// creates its .json.

import Anthropic from "@anthropic-ai/sdk";
import { readdirSync, readFileSync } from "node:fs";
import { basename, extname, join } from "node:path";
import { INSTRUCTIONS, LABEL_SCHEMA, type ExtractedLabel } from "../src/label.ts";
import { EVAL_DIR, FIXTURES_DIR, loadFixtures, loadPhoto, saveFixture, score, type Fixture } from "./lib.ts";

const MODEL = "claude-opus-5-5";
const args = process.argv.slice(2);
const force = args.includes("--force");
const onlyAt = args.indexOf("--only");
const only = onlyAt >= 0 ? args[onlyAt + 1].split(",") : undefined;

// New photos get a fixture file.
const known = new Set(loadFixtures().map((f) => f.photo));
for (const file of readdirSync(FIXTURES_DIR)) {
  if (!/\.(jpe?g|png|webp|heic|heif)$/i.test(file) || known.has(file)) continue;
  saveFixture({ id: basename(file, extname(file)), photo: file, expected: null, verified: false });
  console.log(`New fixture: ${file}`);
}

const rules = readFileSync(join(EVAL_DIR, "reference-rules.md"), "utf8");
const system = `${INSTRUCTIONS}

You are making the reference reading for a test set, so accuracy matters more than anything. Read every digit, decimal point, unit and range carefully, and look again at anything small or blurred. Never guess: leave out a line you can't read with confidence.

These extra rules take precedence:

${rules}`;

const client = new Anthropic();

async function readLabel(fixture: Fixture): Promise<ExtractedLabel> {
  const photo = loadPhoto(join(FIXTURES_DIR, fixture.photo));
  const message = await client.messages
    .stream({
      model: MODEL,
      max_tokens: 32000,
      system,
      output_config: { effort: "high", format: { type: "json_schema", schema: LABEL_SCHEMA as unknown as Record<string, unknown> } },
      messages: [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: photo.mimeType as "image/jpeg", data: photo.base64 } },
          { type: "text", text: "Transcribe the Japanese nutrition facts panel in this photo." },
        ],
      }],
    })
    .finalMessage();
  // No fallback model on purpose: a reading from a different model must never become the reference silently.
  if (message.stop_reason === "refusal") throw new Error("Claude declined this photo");
  if (message.stop_reason === "max_tokens") throw new Error("answer was cut off");
  const text = message.content.find((b) => b.type === "text");
  if (!text || text.type !== "text") throw new Error("no answer");
  return JSON.parse(text.text) as ExtractedLabel;
}

const todo = loadFixtures(only).filter((f) => force || !f.expected);
if (todo.length === 0) console.log("Every fixture already has an expected reading. Use --force to redo some.");

for (const fixture of todo) {
  process.stdout.write(`${fixture.id} `);
  try {
    const [first, second] = await Promise.all([readLabel(fixture), readLabel(fixture)]);
    const differences = score(first, second).checks.filter((c) => c.verdict !== "ok")
      .map((c) => `${c.field}: ${c.expected} vs ${c.actual}`);
    saveFixture({
      ...fixture,
      expected: first,
      verified: false,
      reference: {
        by: `${MODEL}, two independent readings`,
        at: new Date().toISOString(),
        agreement: differences.length === 0 ? "agreed" : "single",
        ...(differences.length ? { disagreements: differences } : {}),
      },
    });
    console.log(differences.length === 0 ? "✓ both readings agree" : `⚠ readings differ: ${differences.join("; ")}`);
  } catch (e) {
    if (e instanceof Anthropic.AuthenticationError || /authentication method/.test((e as Error).message)) {
      console.log("✗\nSet ANTHROPIC_API_KEY to an Anthropic API key (console.anthropic.com).");
      process.exit(1);
    }
    console.log(`✗ ${(e as Error).message}`);
  }
}

// Turns scans exported from the app (debug build: Settings › Debug › Export Scans) into eval fixtures.
//
//   npm run eval:import -- ~/Downloads/"NutriFacts Scans.zip"
//
// Each scan becomes eval/fixtures/own-<date>-<name>.jpg and .json, with no expected reading yet and
// what the app read kept as `appReading` for comparison. Then, as for any new photo:
//   ANTHROPIC_API_KEY=sk-ant-… npm run eval:reference   (expected readings from Claude)
//   npm run eval:review                                (check them against the photos)
//
// own-* fixtures are git-ignored: your photos stay on this Mac. Look at a photo before renaming it to
// commit it, as the background of a real photo can show more than the label.

import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdtempSync, readdirSync, readFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FIXTURES_DIR, saveFixture } from "./lib.ts";

/** Swift's JSONEncoder writes dates as seconds since 2001-01-01. */
const APPLE_EPOCH_MS = Date.UTC(2001, 0, 1);

interface SavedScan {
  date: number;
  panel: { productName?: { japanese: string; english: string } | null };
  /** Swift encodes an enum case without values as { "aiAnd": {} }. */
  readBy?: Record<string, unknown> | null;
  reading?: unknown;
}

/** Folders holding a scan.json, anywhere under `dir`. */
function scanFolders(dir: string): string[] {
  if (existsSync(join(dir, "scan.json"))) return [dir];
  return readdirSync(dir).map((f) => join(dir, f)).filter((p) => statSync(p).isDirectory()).flatMap(scanFolders);
}

/** "Potato Chips Lightly Salted" → "potato-chips-lightly-salted", at most 40 characters. */
export function slug(text: string): string {
  return text.normalize("NFKD").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40).replace(/-$/, "");
}

/** The fixture ID for a scan: own-20261022-1953-potato-chips. */
export function fixtureId(scan: SavedScan): string {
  const d = new Date(APPLE_EPOCH_MS + scan.date * 1000);
  const pad = (n: number) => String(n).padStart(2, "0");
  const stamp = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}`;
  return ["own", stamp, slug(scan.panel.productName?.english ?? "")].filter(Boolean).join("-");
}

if (import.meta.main) {
  const zip = process.argv[2];
  if (!zip) {
    console.error('Usage: npm run eval:import -- ~/Downloads/"NutriFacts Scans.zip"');
    process.exit(1);
  }
  const dir = mkdtempSync(join(tmpdir(), "nutrifacts-scans-"));
  execFileSync("unzip", ["-q", zip, "-d", dir]);

  let added = 0;
  for (const folder of scanFolders(dir)) {
    const scan = JSON.parse(readFileSync(join(folder, "scan.json"), "utf8")) as SavedScan;
    // The whole photo the model read, or only the cropped label for scans from before debug builds kept it.
    const frame = existsSync(join(folder, "frame.jpg"));
    const source = join(folder, frame ? "frame.jpg" : "label.jpg");
    if (!existsSync(source) || !scan.reading) continue; // a sample label from the simulator
    const id = fixtureId(scan);
    if (existsSync(join(FIXTURES_DIR, `${id}.json`))) {
      console.log(`${id} is already a fixture`);
      continue;
    }
    copyFileSync(source, join(FIXTURES_DIR, `${id}.jpg`));
    saveFixture({
      id,
      photo: `${id}.jpg`,
      notes: `Own photo from the app${frame ? "" : " (cropped label only)"}, read by ${Object.keys(scan.readBy ?? {})[0] ?? "unknown"}.`,
      source: { title: scan.panel.productName?.japanese || null, author: "Own photo", license: "Not for redistribution" },
      expected: null,
      verified: false,
      appReading: scan.reading,
    });
    console.log(`Added ${id}${frame ? "" : " (cropped label only)"}`);
    added++;
  }
  console.log(`\n${added} new fixture${added === 1 ? "" : "s"}. Next: ANTHROPIC_API_KEY=sk-ant-… npm run eval:reference, then npm run eval:review.`);
}

// A local page for checking expected readings by eye: each photo next to the values it should
// give. "Matches the photo" marks the fixture verified; "Edit" lets you fix the reading first.
// Changes are written straight to eval/fixtures/<id>.json.
//
//   npm run eval:review            then open http://localhost:4477

import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { extname, join } from "node:path";
import { FIXTURES_DIR, formatLine, loadFixtures, saveFixture, type Fixture } from "./lib.ts";
import { STYLE, ZOOM_SCRIPT } from "./report.ts";

const PORT = Number(process.env.PORT ?? 4477);
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);

function card(f: Fixture): string {
  const e = f.expected;
  const rows = !e ? `<tr><td colspan="2">No expected reading yet. Run <code>npm run eval:reference</code>.</td></tr>`
    : [
        ["Panel found", e.panelFound ? "yes" : "no"],
        ...(e.panelFound ? [
          ["Basis", `${e.basisText || "—"}  →  ${e.basisAmount > 0 ? `${e.basisAmount}${e.basisUnit}` : "no amount"}`],
          ["内容量", e.netContentsAmount > 0 ? `${e.netContentsAmount}${e.netContentsUnit}${e.netContentsCount ? ` (${e.netContentsCount}個)` : ""}` : e.netContentsCount ? `${e.netContentsCount}個` : "—"],
          ["推定値 / 目安", e.isEstimate ? "yes" : "no"],
          ...e.lines.map((l) => [`${l.printedName}${l.nutrient === "other" ? "" : ` <span class="pill">${l.nutrient}</span>`}`, formatLine(l)]),
        ] : []),
      ].map(([k, v]) => `<tr><td>${k}</td><td class="v">${esc(v)}</td></tr>`).join("");
  const flags = [
    f.reference?.disagreements?.length ? `<p class="notes" style="color:var(--bad)">Readings disagreed on: ${esc(f.reference.disagreements.join("; "))}</p>` : "",
    f.notes ? `<p class="notes">${esc(f.notes)}</p>` : "",
  ].join("");
  return `<section class="card ${f.verified ? "" : "fail"}" id="${esc(f.id)}">
<div class="photo"><img loading="lazy" src="/photos/${encodeURIComponent(f.photo)}" alt=""></div>
<div class="body"><div class="head"><h2>${esc(f.id)}</h2>${f.verified ? `<span class="pill ok">verified</span>` : `<span class="pill warn">to check</span>`}</div>
${flags}<table>${rows}</table>
<p style="margin-top:12px; display:flex; gap:8px; flex-wrap:wrap">
${e ? `<button onclick="verify('${esc(f.id)}')">✓ Matches the photo</button>` : ""}<button onclick="this.closest('.body').querySelector('.edit').hidden ^= 1">Edit</button></p>
<div class="edit" hidden><textarea rows="18" style="width:100%; font:12px ui-monospace, Menlo, monospace">${esc(JSON.stringify(e, null, 2))}</textarea>
<p><button onclick="save('${esc(f.id)}', this)">Save as verified</button></p></div></div></section>`;
}

function page(): string {
  const fixtures = loadFixtures().sort((a, b) => Number(a.verified) - Number(b.verified) || Number(!a.reference?.disagreements) - Number(!b.reference?.disagreements));
  const done = fixtures.filter((f) => f.verified).length;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fixture Review</title><style>${STYLE} button { font:inherit; padding:6px 12px; border-radius:8px; border:1px solid var(--line); background:var(--bg); color:var(--ink); cursor:pointer; } textarea { background:var(--bg); color:var(--ink); border:1px solid var(--line); border-radius:8px; padding:8px; }</style></head>
<body><main><h1>Check the expected readings</h1>
<p class="sub">${done} of ${fixtures.length} verified. Compare each value with the photo (click it to zoom). Rules for tricky panels are in eval/reference-rules.md.</p>
${fixtures.map(card).join("\n")}</main><dialog><img alt=""></dialog>
<script>${ZOOM_SCRIPT}
async function post(body) { const r = await fetch("/api/fixture", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }); if (!r.ok) { alert(await r.text()); return false; } return true; }
async function verify(id) { if (await post({ id })) location.reload(); }
async function save(id, button) { let expected; try { expected = JSON.parse(button.closest(".edit").querySelector("textarea").value); } catch (e) { alert("That isn't valid JSON: " + e.message); return; } if (await post({ id, expected })) location.reload(); }
</script></body></html>`;
}

const TYPES: Record<string, string> = { ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp" };

createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", "http://localhost");
  try {
    if (req.method === "GET" && url.pathname === "/") {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" }).end(page());
    } else if (req.method === "GET" && url.pathname.startsWith("/photos/")) {
      const file = decodeURIComponent(url.pathname.slice("/photos/".length));
      if (file.includes("/") || file.includes("..")) throw new Error("bad path");
      res.writeHead(200, { "Content-Type": TYPES[extname(file).toLowerCase()] ?? "application/octet-stream" }).end(readFileSync(join(FIXTURES_DIR, file)));
    } else if (req.method === "POST" && url.pathname === "/api/fixture") {
      let body = "";
      for await (const chunk of req) body += chunk;
      const { id, expected } = JSON.parse(body) as { id: string; expected?: Fixture["expected"] };
      const fixture = loadFixtures([id])[0];
      if (!fixture) throw new Error(`No fixture ${id}`);
      if (expected !== undefined) {
        if (!expected || typeof expected.panelFound !== "boolean" || !Array.isArray(expected.lines)) throw new Error("expected needs panelFound and lines");
        fixture.expected = expected;
      }
      saveFixture({ ...fixture, verified: true, reference: { ...fixture.reference!, ...(expected !== undefined ? { agreement: "resolved" as const } : {}) } });
      res.writeHead(204).end();
    } else {
      res.writeHead(404).end("Not found");
    }
  } catch (e) {
    res.writeHead(400, { "Content-Type": "text/plain" }).end((e as Error).message);
  }
}).listen(PORT, () => console.log(`Review fixtures at http://localhost:${PORT}  (Ctrl-C to stop)`));

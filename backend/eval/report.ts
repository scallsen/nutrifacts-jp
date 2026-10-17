// The run report: one card per photo, the photo next to the expected and returned values.

import type { Result } from "./run.ts";
import { formatLine, pct, type Fixture, type Score, type Summary } from "./lib.ts";

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);

export const STYLE = `
:root { --bg:#f6f5f2; --card:#fff; --ink:#1b1b1a; --muted:#6b6a66; --line:#e3e1dc; --ok:#1f7a4d; --bad:#b42318; --warn:#9a6700; --badbg:#fde8e6; --warnbg:#fff4d6; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#141413; --card:#1e1e1c; --ink:#ecebe7; --muted:#9c9a94; --line:#33322f; --ok:#4cc38a; --bad:#ff8a80; --warn:#e3b341; --badbg:#3a1d1a; --warnbg:#332a12; } }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:14px/1.45 -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Noto Sans JP", sans-serif; }
main { max-width:1200px; margin:0 auto; padding:24px 16px 64px; }
h1 { font-size:22px; margin:0 0 4px; } .sub { color:var(--muted); margin:0 0 20px; }
.stats { display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:10px; margin-bottom:20px; }
.stat { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:12px; }
.stat b { display:block; font-size:22px; } .stat span { color:var(--muted); font-size:12px; }
.bar { display:flex; gap:12px; align-items:center; margin:0 0 14px; color:var(--muted); }
.card { background:var(--card); border:1px solid var(--line); border-radius:12px; margin:0 0 14px; display:grid; grid-template-columns:minmax(0,1fr) minmax(0,1.1fr); overflow:hidden; }
.card.fail { border-color:var(--bad); }
.photo { background:#000; display:flex; align-items:center; justify-content:center; min-height:200px; }
.photo img { max-width:100%; max-height:520px; display:block; cursor:zoom-in; }
.body { padding:14px 16px; min-width:0; }
.head { display:flex; gap:8px; align-items:baseline; flex-wrap:wrap; margin-bottom:6px; }
.head h2 { font-size:15px; margin:0; } .pill { font-size:11px; padding:1px 7px; border-radius:99px; border:1px solid var(--line); color:var(--muted); }
.pill.bad { color:var(--bad); border-color:var(--bad); } .pill.ok { color:var(--ok); border-color:var(--ok); } .pill.warn { color:var(--warn); border-color:var(--warn); }
.notes { color:var(--muted); font-size:12px; margin:0 0 8px; }
table { border-collapse:collapse; width:100%; font-variant-numeric:tabular-nums; }
td, th { text-align:left; padding:4px 6px; border-bottom:1px solid var(--line); vertical-align:top; }
th { font-weight:600; color:var(--muted); font-size:12px; }
tr.wrong td, tr.missing td { background:var(--badbg); } tr.invented td { background:var(--warnbg); }
tr.other td { color:var(--muted); }
.v { font-family:ui-monospace, SFMono-Regular, Menlo, monospace; }
.src { font-size:11px; color:var(--muted); margin-top:8px; word-break:break-all; } .src a { color:inherit; }
body.only-fail .card:not(.fail) { display:none; }
dialog { border:0; padding:0; background:transparent; max-width:96vw; max-height:96vh; } dialog img { max-width:96vw; max-height:96vh; } dialog::backdrop { background:rgba(0,0,0,.85); }
@media (max-width:760px) { .card { grid-template-columns:1fr; } }
`;

export const ZOOM_SCRIPT = `
const dlg = document.querySelector("dialog"), big = dlg.querySelector("img");
document.addEventListener("click", (e) => { if (e.target.matches(".photo img")) { big.src = e.target.src; dlg.showModal(); } else if (e.target.closest("dialog")) dlg.close(); });
`;

export function renderReport(rows: { fixture: Fixture; result: Result; score: Score }[], sum: Summary, photos: string): string {
  const cards = rows.map(({ fixture: f, result: r, score: s }) => {
    const pills = [
      r.error ? `<span class="pill bad">${esc(r.error)}</span>` : s.perfect ? `<span class="pill ok">perfect</span>` : `<span class="pill bad">${s.checks.filter((c) => c.verdict !== "ok").length} wrong</span>`,
      f.verified ? `<span class="pill ok">verified</span>` : `<span class="pill warn">unverified</span>`,
      r.ms ? `<span class="pill">${r.ms} ms</span>` : "",
    ].join(" ");
    const checks = s.checks.map((c) => `<tr class="${c.verdict === "ok" ? "" : c.verdict}"><td>${esc(c.field)}</td><td class="v">${esc(c.expected)}</td><td class="v">${esc(c.actual)}</td><td>${c.verdict === "ok" ? "✓" : esc(c.verdict)}</td></tr>`).join("");
    const others = (f.expected?.lines ?? []).filter((l) => l.nutrient === "other").map((l) => {
      const got = r.label?.lines.find((a) => a.nutrient === "other" && a.printedName === l.printedName);
      return `<tr class="other"><td>${esc(l.printedName)}</td><td class="v">${esc(formatLine(l))}</td><td class="v">${esc(formatLine(got))}</td><td>not scored</td></tr>`;
    }).join("");
    const basisText = f.expected?.panelFound ? `<p class="notes">Basis printed: <b>${esc(f.expected.basisText || "—")}</b> · returned: ${esc(r.label?.basisText || "—")}</p>` : "";
    const src = f.source ? `<div class="src">${esc(f.source.license)} · ${esc(f.source.author)} · <a href="${esc(f.source.page)}">${esc(f.source.page)}</a></div>` : "";
    return `<section class="card ${s.perfect && !r.error ? "" : "fail"}">
<div class="photo"><img loading="lazy" src="${esc(`${photos}/${f.photo}`)}" alt="${esc(f.id)}"></div>
<div class="body"><div class="head"><h2>${esc(f.id)}</h2>${pills}</div>
${f.notes ? `<p class="notes">${esc(f.notes)}</p>` : ""}${basisText}
<table><tr><th>Check</th><th>Expected</th><th>Service</th><th></th></tr>${checks}${others}</table>${src}</div></section>`;
  }).join("\n");

  const stat = (value: string, label: string) => `<div class="stat"><b>${value}</b><span>${label}</span></div>`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Label Reading Eval</title><style>${STYLE}</style></head><body><main>
<h1>Label reading eval</h1><p class="sub">${rows.length} photos sent to the NutriFacts API and compared with the expected readings.</p>
<div class="stats">${stat(pct(sum.perfect, sum.fixtures), `labels read perfectly (${sum.perfect}/${sum.fixtures})`)}${stat(pct(sum.valuesCorrect, sum.values), `nutrient values right (${sum.valuesCorrect}/${sum.values})`)}${stat(String(sum.invented), "invented lines")}${stat(pct(sum.panelCorrect, sum.panelChecks), "panel found / not found right")}${stat(pct(sum.basisCorrect, sum.basisChecks), "basis amount right")}</div>
<label class="bar"><input type="checkbox" onchange="document.body.classList.toggle('only-fail', this.checked)"> Show only labels with mistakes</label>
${cards}</main><dialog><img alt=""></dialog><script>${ZOOM_SCRIPT}</script></body></html>`;
}

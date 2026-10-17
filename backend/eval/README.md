# Label reading eval

Checks how accurately the NutriFacts API reads real Japanese nutrition labels. Each fixture is a
real photo with the reading it should give. `npm run eval` sends every photo to the deployed
Worker, the same request the app makes, and scores the answer value by value.

```bash
cd backend
npm run eval                    # ~7 min: the Worker allows 10 reads a minute
npm run eval:review             # check expected readings by eye at http://localhost:4477
npm run eval:reference          # make expected readings for new photos (needs ANTHROPIC_API_KEY)
```

`npm run eval` prints every mistake and a summary, and writes `eval/runs/<time>/report.html` with
each photo next to the expected and returned values. `--only id,id` runs a few fixtures,
`--verified` skips fixtures nobody has checked yet, `--rescore eval/runs/<time>` re-scores a saved
run without new requests, and `--fail-under 95` exits 1 when fewer than 95% of values are right.

## Trying prompt, model and reasoning changes

`--direct` skips the Worker and sends the photos straight to AI& with this checkout's prompt, schema
and parsing (`src/label.ts`), four at a time. Use it to compare changes before deploying:

```bash
echo 'AIAND_API_KEY=sk-…' > .dev.vars          # once; git-ignored, also used by `npm run dev`
npm run eval -- --direct                        # the deployed model (wrangler.jsonc) with this prompt
npm run eval -- --direct --model google/gemma-4-31b-it
npm run eval -- --direct --reasoning high       # reasoning_effort; levels per model in /v1/models
```

The summary adds token counts so you can weigh accuracy against cost. To ship a winner, set
`AIAND_MODEL` / `AIAND_REASONING_EFFORT` in `wrangler.jsonc` and `npm run deploy`, then run
`npm run eval` once more against the deployed Worker.

## What's scored

| Check | Pass when |
|---|---|
| Panel found | `panelFound` matches. Photos without a Japanese panel (a foreign panel, a front, an ingredients block) must give `false`. |
| Each nutrient line | Same nutrient, same unit, same min and max. `other` lines (vitamins, minerals, コレステロール …) are shown but not scored. |
| Invented line | A scored nutrient the label doesn't print. The worst mistake: the app would show a value that isn't there. |
| Basis | `basisAmount` and its unit, or no amount for `1個当たり`. |
| 推定値 / 内容量 | `isEstimate`, and 内容量 amount, unit and piece count. |

A label is *perfect* when every check passes.

## Fixtures

`eval/fixtures/<id>.jpg` and `<id>.json`. The JSON holds the source and licence, notes on what the
photo tests, the `expected` reading (same shape as the API's answer), how it was made, and
`verified`.

The current 57 photos come from [Open Food Facts](https://world.openfoodfacts.org) (CC BY-SA 3.0)
and [Wikimedia Commons](https://commons.wikimedia.org) (CC BY-SA, CC0 or public domain; each
fixture names its author). Like the app, the eval sends them at most 2048 px on the long side. They
cover simple tables, inline sentence panels, 糖質/食物繊維 nesting, ranges (`0〜1.6g`), ナトリウム-only
labels, `1個当たり` bases with no grams, grouped zeros, two-column panels, natto with a たれ column,
cup noodles with split salt, blurred, glared and tilted photos, and 7 photos that must give no panel.

### How expected readings are made

Claude Opus 5.5 reads each photo twice, independently, with the Worker's own instructions plus
[`reference-rules.md`](reference-rules.md) for cases the Worker's prompt doesn't settle yet (which
column of a two-column panel, salt breakdowns, foreign panels). Where the two readings agree, that's
the expected reading. Where they don't, the first is kept and the differences are listed for review.
Either way a fixture stays `verified: false` until a person has compared it with the photo in
`npm run eval:review`. The report marks unverified fixtures, and `--verified` leaves them out.

### Adding photos

1. Put the photo in `eval/fixtures/` with a short descriptive name (`natto-3-pack.heic`). Photos you
   took yourself are best: they're what the app actually sees.
2. `ANTHROPIC_API_KEY=sk-ant-… npm run eval:reference` creates its `.json` and expected reading.
3. `npm run eval:review` to check it against the photo, fix it if needed, and mark it verified.

## Ingredients box eval

`npm run eval:box` reads the ingredients box (一括表示) photos in `eval/box/` with
`/v1/ingredients-box/read`, or with `--direct` straight from AI& with this checkout's prompt
(`src/ingredients.ts`). It takes `--model`, `--reasoning`, `--only` and `--fail-under` like `npm run eval`.

Each fixture in `eval/box/<id>.json` names a photo in `eval/fixtures/` and holds the expected reading.
The scoring:

| Check | Pass when |
|---|---|
| Box found | `boxFound` matches. A photo with no box must give `false`. |
| Ingredient | Each expected ingredient comes back with the same Japanese (NFKC, spaces ignored), in any order. Extras count as invented. |
| Allergen | Each allergen comes back, with 乳成分 = 乳 and ピーナッツ = 落花生. A missed allergen is the worst mistake. |
| Net contents | Amount, unit, count and "printed elsewhere". |
| Food type, date, additives | 名称, use by vs best before, and the additive flags (only on boxes with a ／ or 添加物 line). |

English translations aren't scored. The run prints them to read by eye. The 6 current expected
readings were made by Claude Opus 5.5 from the photos and aren't verified yet.

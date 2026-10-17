# ai& Backend

The app's **ai&** option reads labels with a vision model on [AI&](https://www.aiand.com/jp/), a Japanese inference provider with an OpenAI-compatible API. The app never calls AI& directly. It calls the **NutriFacts API**, a small Cloudflare Worker in [`backend/`](../backend/), which holds the AI& key.

```
App ──photo──▶ NutriFacts API (Cloudflare Worker) ──photo + prompt + schema──▶ AI& /v1/chat/completions
    ◀─label───                                   ◀──────── JSON label ────────
```

- **The AI& key** is a Worker secret, never in the app or in git.
- **The Worker only reads labels.** It sets the model, the prompt and a strict JSON schema itself, so its URL can't be used to run arbitrary prompts on your AI& credit.
- **Rate limit:** 10 reads a minute per client IP (`READ_LIMITER` in `wrangler.jsonc`).
- **Optional app token:** if the Worker has an `APP_TOKEN` secret, requests need a matching `X-App-Token` header. The app sends it from `App/Config/Secrets.xcconfig`. It ships inside the app, so it only keeps out casual traffic. Apple App Attest is the stronger option if abuse becomes a problem.
- **Scoring stays in the app.** The Worker returns a transcription, and the app scores it with [`data/health-score.json`](../data/health-score.json), exactly as for Apple's models.

Setup steps are in [`backend/README.md`](../backend/README.md).

## API

```
POST {NUTRIFACTS_API_URL}/v1/nutrition-label/read
Content-Type: application/json
X-App-Token: {token}          (only if the Worker has APP_TOKEN)

{ "image": "<base64 JPEG, PNG or WebP>", "mimeType": "image/jpeg", "reasoningEffort": "low" }
```

The app downscales photos to 2048 px on the long side. The Worker rejects images over 8 MB.

`reasoningEffort` is optional, and it's the level picked in the app's Settings. The Worker uses it only if the model offers it, and otherwise falls back to `AIAND_REASONING_EFFORT` (`low`). If the model doesn't offer that either, it sends nothing and AI& uses the model's own default. (`qwen/qwen3.8-27b` defaults to `xhigh`, which is slow, and reasoning is billed as output.) The response's `X-Reasoning-Effort` header says which level AI& applied.

### `GET /v1/config`

What Settings offers in the Reasoning picker:

```json
{ "model": "qwen/qwen3.8-27b", "reasoningEfforts": ["none", "low", "medium", "xhigh"], "defaultReasoningEffort": "low" }
```

The levels come from AI&'s model list and are cached for an hour, so the picker follows the Worker's model when you change it.

### `200 OK`: the transcription

```json
{
  "panelFound": true,
  "productName": "ポテトチップス",
  "basisText": "1袋（60g）当たり",
  "basisAmount": 60,
  "basisUnit": "g",
  "netContentsAmount": 60,
  "netContentsUnit": "g",
  "netContentsCount": 0,
  "isEstimate": true,
  "lines": [
    { "nutrient": "energy",       "printedName": "熱量",       "minValue": 336,  "maxValue": 336,  "unit": "kcal" },
    { "nutrient": "protein",      "printedName": "たんぱく質", "minValue": 3.1,  "maxValue": 3.1,  "unit": "g" },
    { "nutrient": "fat",          "printedName": "脂質",       "minValue": 21.6, "maxValue": 21.6, "unit": "g" },
    { "nutrient": "carbohydrate", "printedName": "炭水化物",   "minValue": 32.4, "maxValue": 32.4, "unit": "g" },
    { "nutrient": "salt",         "printedName": "食塩相当量", "minValue": 0.6,  "maxValue": 0.6,  "unit": "g" }
  ]
}
```

| Field | Rule |
|---|---|
| `panelFound` | `false` when there's no 栄養成分表示 panel. That's legal for some products, so it isn't an error; `lines` is empty. |
| `basisText` | Only the per-what phrase, e.g. `1食分（50g）当たり` or `1個当たり`, without 栄養成分表示 or outer brackets. |
| `basisAmount` | Grams or ml in the basis text. `0` when the basis gives none (`1個当たり`). Never filled from 内容量. The app shows the label as printed and asks the user to confirm a size. |
| `netContentsAmount` / `netContentsUnit` | 内容量 as a weight or volume (`g` or `ml`), if it's in the photo. `0` / `none` when it isn't, or when it's only a count (`2個`). The app offers it as a suggestion. |
| `netContentsCount` | Pieces in the pack if 内容量 says (`6個入り` → 6), else `0`. The suggestion becomes 内容量 ÷ count. |
| `lines` | **Only lines that are printed.** A missing line is "not disclosed", never 0. |
| `nutrient` | `energy`, `protein`, `fat`, `saturatedFat`, `carbohydrate`, `netCarbs` (糖質), `sugars` (糖類), `fibre`, `salt` (食塩相当量), `sodium` (ナトリウム) or `other`. |
| `minValue` / `maxValue` | Equal for a single value; the two ends for a range (`120〜150`). A printed `0` is `0`. |
| `unit` | As printed: `kcal`, `kJ`, `g`, `mg`, `µg`. |

The schema lives in two places that must match: `backend/src/label.ts` (sent to AI&) and `ExtractedLabel` in `App/NutriFacts/Reading/ExtractedLabel.swift` (filled by Apple's models, and decoded from this response).

### Errors

`{ "error": { "message": "…" } }`. The message is written for the user, and the app shows it as is.

| Status | When |
|---|---|
| 400 | Bad body, or AI& couldn't read the photo |
| 401 | Missing or wrong `X-App-Token` |
| 413 | Image over 8 MB |
| 429 | This client's rate limit, or AI& is busy |
| 500 | The Worker has no `AIAND_API_KEY` or `AIAND_MODEL` |
| 502 | AI& failed or returned something unreadable |
| 503 | AI& rejected the key, is out of credit, or the model can't take images. The details go to the Worker's logs, not to the client. |

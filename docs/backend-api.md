# ai& Backend Contract

The iPhone app can read labels through an HTTP backend instead of Apple's models. It sends the screenshot and gets back a **transcription** of the panel. The backend doesn't score; the app does that itself with [`data/health-score.json`](../data/health-score.json), so every backend grades the same panel the same way ([`health-score.md`](health-score.md)).

The base URL and API key are set in the app's Settings (the key is stored in the Keychain).

## Request

```
POST {baseURL}/v1/nutrition-label/read
Authorization: Bearer {apiKey}
Content-Type: application/json
```

```json
{
  "image": "<base64 JPEG>",
  "mimeType": "image/jpeg",
  "ocrText": "栄養成分表示\n1袋（60g）当たり\n熱量 336kcal\n…",
  "locale": "ja-JP",
  "schemaVersion": 1
}
```

`ocrText` is Apple Vision's on-device OCR of the same image. It may contain misreads; the image wins when they disagree.

## Response: `200 OK`

```json
{
  "panelFound": true,
  "productName": "ポテトチップス",
  "basisText": "1袋（60g）当たり",
  "basisAmount": 60,
  "basisUnit": "g",
  "netContentsAmount": 60,
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
| `panelFound` | `false` when there's no 栄養成分表示 panel. That's legal for some products, so it isn't an error; send `lines: []`. |
| `basisAmount` | Grams or ml in the basis text. `0` when the basis gives none (`1袋当たり`). Never fill it from 内容量: put that in `netContentsAmount` and the app asks the user. |
| `basisUnit` | `g` or `ml` (drinks). |
| `lines` | **Only lines that are printed.** A missing line is "not disclosed", never 0 (rule 3). |
| `nutrient` | One of `energy`, `protein`, `fat`, `saturatedFat`, `carbohydrate`, `netCarbs` (糖質), `sugars` (糖類), `fibre`, `salt` (食塩相当量), `sodium` (ナトリウム), `other`. Never map 糖質 to `sugars`. |
| `minValue` / `maxValue` | Equal for a single value; the two ends for a range (`120〜150`). A printed `0` is `0`. |
| `unit` | As printed: `kcal`, `kJ`, `g`, `mg`, `µg`. Sodium switches to `g` at ≥ 1000 mg. |

The same schema is the `@Generable` type the Apple backends fill (`ios/NutrifactsJP/Extraction/ExtractedLabel.swift`), so the field descriptions there double as extraction instructions.

## Errors

Any non-2xx status is shown to the user as "The ai& backend returned HTTP {code}". The app times out after 30 seconds.

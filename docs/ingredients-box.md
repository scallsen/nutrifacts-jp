# Pack Size and the Ingredients Box (一括表示)

Status: step 1 (typed pack size) is built. Step 2 is built in the app with Apple Intelligence only: `ExtractedIngredientsBox` holds the schema and prompt. The ai& Worker doesn't have the route yet.

## The problem

The nutrition panel prints a **basis** (`100ml当たり`, `1食分（30g）当たり`, `1個当たり`). The **whole pack** size is 内容量 (net contents), and it's usually printed somewhere else:

- In the ingredients box (一括表示), next to 原材料名. This is the usual place for snacks and packaged food.
- On the front, near the brand (`500ml`). This is common on PET bottles and cans.
- Elsewhere on the pack, with the box pointing to it: `内容量：キャップに記載`, `欄外下部に記載`, `表面に記載`.

A 500 ml drink labelled per 100 ml is the typical case. The panel is accurate, but nobody drinks 100 ml, and the whole-bottle numbers need the 500.

What the app does today:
- Every reader already asks for 内容量. When the photo happens to include it in the same unit as the basis, it becomes `packAmount`, and the **Whole pack** tab appears.
- When the basis has no size (`1個当たり`), 内容量 (÷ the piece count) is only offered as a suggestion for the basis size.
- When 内容量 isn't in the photo, there's no whole-pack view.

## Step 1 (built): type the pack size

The result screen has a **Pack Size** row under the size tabs. It shows only when the basis size is known.

- Tapping it opens an alert with a number field, in the label's unit (g or ml).
- Saving it sets `packAmount` (`LabelPanel.setPack`). That adds the **Pack · 500 ml** tab and switches to it.
- A pack read from the photo shows in the same row, so it can be corrected.
- Zeros scale the same way as on the other tabs. A printed 0 still shows as "0 g" and "Low", because the label only promises "below the threshold per 100 g/ml".

## Step 2: scan the ingredients box

A second, optional scan from the result: **Scan Ingredients**. It reads the 一括表示 and does two things:

1. It fills 内容量. This sets `packAmount`, or the basis suggestion for `1個当たり`. It never overwrites a size the user typed.
2. It shows a second table: name, ingredients, allergens, net contents, best before, storage and maker, in English, with the Japanese behind the existing "Show Japanese terms" setting.

### What the box contains

Required by 食品表示基準 for packaged processed food, usually in this order. The headings are printed, so they're reliable anchors for the model and for the camera.

| Heading | Meaning | Notes |
|---|---|---|
| 名称 (or 品名, 種類別) | Food category, not the brand | e.g. 清涼飲料水, スナック菓子, 種類別 牛乳 |
| 原材料名 | Ingredients, heaviest first | Compound ingredients nest in brackets: `チョコレート（砂糖、カカオマス、…）` |
| 添加物 | Additives | Either a separate line, or after a `／` in 原材料名 (rule since 2020) |
| (allergens) | | Inside 原材料名, either per item `（小麦を含む）` or one summary at the end: `（一部に小麦・乳成分・大豆を含む）` |
| 原料原産地名 | Origin of the main ingredient | Often in brackets after it: `豚肉（国産）`, `（アメリカ又は国産）` |
| 内容量 | Net contents | See the formats below |
| 固形量 / 内容総量 | Drained weight / total weight | Canned food in liquid prints these instead of 内容量 |
| 賞味期限 / 消費期限 | Best before / use by | Usually "欄外上部に記載" (printed elsewhere), not a date |
| 保存方法 | Storage | e.g. 直射日光、高温多湿を避けて保存してください |
| 製造者 / 販売者 / 輸入者 / 加工者 | Maker, seller, importer or processor | Name and address. `+A1`-style codes are factory codes (製造所固有記号) |
| 原産国名 | Country of origin | Only on imports |

Formats of 内容量 the reader has to handle:

| Printed | Amount | Unit | Count |
|---|---|---|---|
| `500ml` | 500 | ml | 0 |
| `1.5L` | 1500 | ml | 0 |
| `60g` | 60 | g | 0 |
| `1kg` | 1000 | g | 0 |
| `120g（6個入）` | 120 | g | 6 |
| `10袋入` | 0 | none | 10 |
| `2個` | 0 | none | 2 |
| `固形量 200g 内容総量 300g` | 300 | g | 0 |
| `キャップに記載` / `欄外に記載` | 0 | none | 0, with `printedElsewhere` set |

The 8 allergens that must be labelled (特定原材料) are えび, かに, くるみ, 小麦, そば, 卵, 乳 (printed as 乳成分) and 落花生 (ピーナッツ). There are 20 more that are recommended, not required: アーモンド, あわび, いか, いくら, オレンジ, カシューナッツ, キウイフルーツ, 牛肉, ごま, さけ, さば, 大豆, 鶏肉, バナナ, 豚肉, まつたけ, もも, やまいも, りんご and ゼラチン. A pack that names none of these hasn't promised it's free of them. The app should say "Allergens listed", never "Allergen-free".

### Schema

Like the panel, this is a transcription: nothing inferred, nothing scored. The one addition is an English translation of each text field. The translation is generated, so the app should label it that way.

```swift
@Generable
nonisolated struct ExtractedIngredientsBox: Codable, Sendable, Hashable {
    @Guide(description: "True only if a Japanese ingredients box (一括表示, with 名称 and 原材料名) is visible.")
    var boxFound: Bool

    @Guide(description: "名称, 品名 or 種類別, as printed, e.g. 清涼飲料水. Empty if not printed.")
    var category: TranslatedText

    @Guide(description: "Each top-level ingredient from 原材料名, in printed order. Keep a compound ingredient's bracketed contents in its text. Additives are the items after ／ or on the 添加物 line.")
    var ingredients: [ExtractedIngredient]

    @Guide(description: "Allergens the box names, in its own words, e.g. 小麦 or 乳成分. Empty if none are named.")
    var allergens: [String]

    @Guide(description: "内容量 exactly as printed, e.g. 120g（6個入）. Empty if not printed.")
    var netContentsText: String

    @Guide(description: "Weight or volume in 内容量, in g or ml. Convert L to ml and kg to g. For canned food use 内容総量. 0 if only a count or not printed.")
    var netContentsAmount: Double

    var netContentsUnit: ExtractedContentsUnit   // g, ml or none

    @Guide(description: "Pieces or packets if 内容量 says, e.g. 6 for 6個入, else 0.")
    var netContentsCount: Int

    @Guide(description: "True if 内容量 says it's printed elsewhere, e.g. キャップに記載 or 欄外に記載.")
    var netContentsPrintedElsewhere: Bool

    @Guide(description: "賞味期限 or 消費期限 as printed, including 欄外に記載. Empty if not printed.")
    var dateText: TranslatedText
    @Guide(description: "True for 消費期限 (use by), false for 賞味期限 (best before).")
    var isUseBy: Bool

    var storage: TranslatedText        // 保存方法
    var maker: String                  // 製造者 etc., as printed, with the role word
    var countryOfOrigin: TranslatedText // 原産国名, empty unless imported
}

@Generable
nonisolated struct ExtractedIngredient: Codable, Sendable, Hashable {
    var japanese: String   // as printed, e.g. 砂糖 or 豚肉（国産）
    var english: String    // plain English, e.g. sugar or pork (Japan)
    var isAdditive: Bool
}

@Generable
nonisolated struct TranslatedText: Codable, Sendable, Hashable {
    var japanese: String
    var english: String
}
```

Splitting the ingredients into items (instead of one string) lets the app render a list and look up allergens and additives per item. The split is only at top-level `、`, so compound ingredients stay whole, and the model never has to restructure anything.

### Prompt

The same structure as `AppleIntelligenceReader.instructions`, so it works with every reader: PCC, on-device and the AI& Worker.

```
You transcribe the Japanese ingredients box (一括表示) on food packaging into structured data,
and give a plain English translation of each text field. You never judge the food, and you
never fill in anything that isn't printed.

Rules:
- Only read the box with headings such as 名称, 原材料名, 内容量, 賞味期限, 保存方法, 製造者.
  Ignore the nutrition panel (栄養成分表示), marketing text and recycling marks.
- category is 名称, 品名 or 種類別. It's a food type such as 清涼飲料水, not the brand.
- ingredients: split 原材料名 at top-level 、 only. Keep anything in brackets with its ingredient,
  e.g. チョコレート（砂糖、カカオマス） is one item. Items after ／, or on a 添加物 line, are additives.
- Translate ingredients into the plain English name a shopper would know, e.g. 砂糖 sugar,
  ぶどう糖果糖液糖 high-fructose corn syrup, 乳化剤 emulsifier, 香料 flavouring. Keep origins:
  豚肉（国産） is "pork (Japan)". Don't add or drop ingredients.
- allergens: only those the box names, e.g. （一部に小麦・乳成分・大豆を含む） gives 小麦, 乳成分, 大豆.
  Never add an allergen because an ingredient might contain it.
- 内容量: copy it exactly into netContentsText. Convert L to ml and kg to g. 120g（6個入） is
  120 g with count 6. A bare count such as 2個 or 10袋入 has amount 0 and unit none.
  For 固形量 and 内容総量, use 内容総量. If it says it's printed elsewhere (キャップに記載,
  欄外に記載, 表面に記載), set netContentsPrintedElsewhere and leave the amount 0.
- 賞味期限 and 消費期限 are usually printed elsewhere ("欄外上部に記載"). Copy what the box says.
- Convert full-width digits (０-９, ．) to normal numbers.
- If there is no ingredients box in the image, set boxFound to false and leave everything empty.
```

User message: `Transcribe the Japanese ingredients box in this photo.` For the on-device fallback on iOS 26, use `Transcribe the Japanese ingredients box from this OCR of a photo (it may contain misreads):` followed by the OCR text.

### How it fits the app

- **Reader.** Make `LabelReader` generic over what it reads: panel or box. The Apple readers already take a `@Generable` type and instructions, so they need no new code. The Worker needs a separate route, `POST /v1/ingredients-box/read`, with its own fixed schema and prompt. A separate route keeps the Worker from running arbitrary prompts.
- **Camera.** `CameraEngine.panelWords` gets a second set for the box: 原材料名, 名称, 内容量, 賞味期限. The scanning sheet says "Point at the ingredients box".
- **Merge.** `Scan` gets `var box: ExtractedIngredientsBox?`. When 内容量 is in the basis unit and the user hasn't typed a pack size, it sets `packAmount`. For `1個当たり`, it fills `basisSuggestion` the way 内容量 from the panel photo does now.
- **Result.** A new section, **Ingredients**, sits below the carb breakdown. It holds name, ingredients (English, with Japanese underneath when the setting is on, and additives marked), "Allergens listed", net contents, best before and storage. Until there's a box, the section is a single **Scan Ingredients** button.
- **One photo, two boxes.** Many snack bags print the panel and the box side by side. The panel reader already picks up 内容量 from that photo. A later version could run both prompts on the same photo, but the box prompt is too long to merge into the panel prompt reliably.

### Risks

- **Length.** Ingredient lists run to 40+ items. With translation, the output can exceed what the on-device model handles well (4,096-token context on iOS 26). Recommend PCC or ai& for this scan, and show a clear error when the list is cut off.
- **Translation.** Additive names (e.g. 加工でん粉, ｐＨ調整剤) need care. Mark the English as translated, and keep the Japanese one tap away.
- **Allergens.** This is the field that can hurt someone. Only show allergens the box names, always next to the printed Japanese, and never as "free from".
- **Untested.** The prompt hasn't been run on real packs yet. The next step is 10 to 20 photos (drinks, snacks, canned food, imports) through `backend/scripts/compare-models.ts` with this schema.

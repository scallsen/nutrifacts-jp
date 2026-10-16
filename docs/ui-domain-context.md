# Domain Context for UI Work

**Read this before designing or building any screen in this app.** It covers what the numbers on a Japanese nutrition label mean, what the *absence* of a line means, and what a UI is allowed to claim from them. Getting these wrong produces screens that look fine but tell users false things.

The underlying regulations, with the full tables and sources, are in [`japanese-nutrition-label-spec.md`](./japanese-nutrition-label-spec.md). A working interactive prototype of the "simplified view" is at [`../prototypes/label-explainer.html`](../prototypes/label-explainer.html); open it in a browser, or see the published version: https://claude.ai/artifact/PtqGn8cchaKZ1Q6kmiKJCW.

---

## 1. What the app does

The user photographs the nutrition panel (栄養成分表示) on a Japanese food package. The app parses it and shows a **simplified view**. That view explains what the label says, fills gaps Japanese labels leave (daily-value %, sodium in mg, per-100 g normalisation), and is honest about what the label does **not** disclose.

Target users are mainly non-Japanese speakers living in or visiting Japan, plus anyone tracking macros, carbs, sugar or salt.

---

## 2. The panel, as printed

```
栄養成分表示
1食分（50g）当たり          ← basis: what amount the numbers describe
熱量         220kcal        ← energy
たんぱく質     4.3g          ← protein
脂質          7.6g          ← fat
 －飽和脂肪酸   2.9g          ← saturated fat (part of fat)
炭水化物       36.0g         ← carbohydrate (INCLUDES fibre)
 －糖質        32.1g         ← net carbs (part of carbohydrate)
  －糖類       11.2g         ← sugars (part of 糖質)
 －食物繊維     3.9g          ← fibre (part of carbohydrate)
食塩相当量      0.2g          ← salt equivalent, NOT sodium
推定値                        ← "estimate": values were calculated, not lab-tested
```

- **Five rows are mandatory and always in this order:** 熱量, たんぱく質, 脂質, 炭水化物, 食塩相当量. Everything else is optional.
- Indent, "－" or brackets mean **"of which"**. The data is a tree, not a flat list.
- There is **no %DV** on Japanese labels.
- It can also be printed inline:
  `栄養成分表示（1袋（60g）当たり）／熱量 336kcal、たんぱく質 3.1g、脂質 21.6g、炭水化物 32.4g、食塩相当量 0.6g（推定値）`
- Zeros can be grouped: `たんぱく質・脂質 0g` means both are 0.

---

## 3. The carbohydrate tree: the most important thing in this doc

```
炭水化物  carbohydrate (total, includes fibre)
├── 糖質  net carbs: starch, sugars, oligosaccharides, sugar alcohols
│   └── 糖類  sugars: mono- and disaccharides only, NOT sugar alcohols
└── 食物繊維  fibre
```

**Identity:** `炭水化物 = 糖質 + 食物繊維`. It's exact by definition (糖質 is calculated as carbohydrate minus fibre) and matches on the label up to rounding.
**Containment:** `糖類 ≤ 糖質 ≤ 炭水化物`.

| Term | English for UI | Includes | Excludes |
|---|---|---|---|
| 炭水化物 | **Carbohydrate** (or "Total carbs") | Everything, including fibre | n/a |
| 糖質 | **Net carbs** | Starch, sugars, oligosaccharides, sugar alcohols | Fibre |
| 糖類 | **Sugars** | Glucose, fructose, sucrose, lactose, maltose, both natural and added | Sugar alcohols, starch |
| 食物繊維 | **Fibre** | Dietary fibre | n/a |

**Never label 糖質 as "sugar".** It's the most common mistranslation, and it's wrong. 糖質 includes starch and sugar alcohols.
**Never label 糖類 as "added sugar".** Japan has no added-sugar line. 糖類 includes the sugars that are naturally in fruit and milk.

### Which lines appear: the disclosure rules
1. **糖質 and 食物繊維 always appear together.** If either is shown, both are.
2. **糖類 can appear on its own** under 炭水化物, with no 糖質 or fibre lines.
3. **Most labels show only 炭水化物.** Fibre is "recommended", not required.

That leaves **exactly four carb disclosure states**. Every UI that shows carbs must handle all four:

| State | Lines present | What we know | What we don't know | Net-carb display |
|---|---|---|---|---|
| **A. Total only** | 炭水化物 | Total carbs, including fibre | Sugar, fibre, net carbs | Range `0 – C` g |
| **B. Sugars only** | 炭水化物, 糖類 | Total, and how much of it is sugar | How the rest (`C − S`) splits between starch, fibre and sugar alcohols | Range `S – C` g |
| **C. Split, no sugars** | 炭水化物, 糖質, 食物繊維 | Net carbs and fibre exactly | How much of the net carbs is sugar (anywhere from 0 to 糖質) | Exact: 糖質 |
| **D. Full** | 炭水化物, 糖質, 糖類, 食物繊維 | Everything: sugar, other net carbs (`糖質 − 糖類`), fibre | Nothing | Exact: 糖質 |

### The absence-means rules (copy these into UI logic)
- **No fibre line → fibre is *not disclosed*. It is not zero.** Don't show "0 g fibre", and never subtract 0 to get net carbs.
- **No 糖類 line → sugar is *not disclosed*. It is not zero.** It can be anywhere from 0 up to 糖質 (or up to 炭水化物 if 糖質 isn't shown either).
- **糖質 shown but no 糖類 →** you know net carbs exactly, but not how much is sugar.
- **糖類 shown without 糖質 →** the remainder `C − S` is "starch, fibre and/or sugar alcohols, mix unknown". Don't call it "starch".
- **A large gap between 糖質 and 糖類** (e.g. 糖質 6.4 g, 糖類 0.9 g) in a low-carb or "糖質オフ" product usually means **sugar alcohols** (erythritol, maltitol). Those count as 糖質, but not as sugar, and they have fewer calories.

### Recommended visual: the carbohydrate bar
One horizontal bar whose width is 炭水化物, split into segments:
- **Sugars** (糖類): solid colour
- **Other net carbs** (糖質 − 糖類): solid colour
- **Fibre** (食物繊維): solid colour
- **Not disclosed**: a hatched or striped pattern, clearly not a nutrient colour, labelled "not disclosed" / "split not disclosed"

| State | Segments |
|---|---|
| A | `[ hatched: sugars, starch, fibre not disclosed ]` |
| B | `[ sugars ][ hatched: starch + fibre, split not disclosed ]` |
| C | `[ net carbs, sugar share not stated ][ fibre ]` |
| D | `[ sugars ][ other net carbs ][ fibre ]` |

The hatching is the core idea of the simplified view. Users should be able to *see* how much of the carb figure the label actually explains.

---

## 4. Other technicalities the UI must respect

### "0" is not zero
A label may print `0` when the amount is below these thresholds **per 100 g (or 100 ml)**:

| Nutrient | "0" means less than |
|---|---|
| Energy | 5 kcal |
| Protein, fat, carbs, 糖質, 糖類, fibre | 0.5 g |
| Saturated fat | 0.1 g |
| Sodium | 5 mg (so salt shows as 0 or 0.0) |

Example: a 500 ml "zero calorie" cola printing 0 kcal per 100 ml can contain **up to 25 kcal per bottle**. When scaling a zero up to a whole pack, show it as `< X` (e.g. "under 25 kcal"), not "0".

### Salt, not sodium
`sodium (mg) = salt (g) × 1000 ÷ 2.54`, roughly salt × 394. Show both: "0.6 g salt · ≈ 236 mg sodium". Salt is printed to 1 decimal place, so the sodium figure is approximate; use "≈".

### The basis varies by product
Numbers may be per 100 g, per 100 ml, per serving (with the serving weight), per pack or per piece. The manufacturer chooses, and **there's no standard serving size**.
- Always show which basis is on screen.
- Offer **As labelled / Per 100 g (ml) / Whole pack**. Per-100 g is the only fair way to compare two products.
- The whole-pack figure needs the net contents (内容量). It's often printed elsewhere on the pack, not in the panel, so the UI may have to ask the user or read a second region of the photo.
- Drinks use ml. Don't relabel them as grams.

### Estimates (推定値 / この表示値は、目安です)
Very common. The values were calculated from ingredient tables or a sample, not lab-tested for this batch. Show a quiet "Estimated values" badge. It isn't a warning or an error.

### Accuracy
Even lab-tested values may legally differ from reality by **±20%**. Don't display more precision than the label gives, and don't treat small differences between products as meaningful.

### Precision varies within one label
Most values are whole numbers, but sub-1 g values must show at least one significant figure (0.4 g, 0.03 g), and salt always has 1 decimal place. Store values as decimals and format per nutrient.

---

## 5. Daily values (%DV)

> The values below are Japan's, the app's default. Every supported standard (Japan, EU, US, Canada), with versions and mapping rules, is in [`data/daily-values.json`](../data/daily-values.json) and [`daily-values.md`](daily-values.md). Use those files, not this table, in code.

Japanese labels don't print them. Compute them from the official **栄養素等表示基準値 (2025)**, for adults aged 18+ at 2,200 kcal:

| Nutrient | Reference |
|---|---|
| Energy | 2,200 kcal |
| Protein | 85 g |
| Fat | 70 g |
| Saturated fat | 17 g |
| Carbohydrate | 320 g |
| Fibre | 20 g |
| Salt | 7.0 g (sodium 2,700 mg) |
| **Sugars (糖類), net carbs (糖質)** | **No reference value. Show "no reference", not a %.** |

If the product wants a sugar %, that's a product decision (e.g. WHO free sugars < 50 g). The UI must name that source, because it isn't Japanese law.

---

## 6. Front-of-pack claims (useful as badges)

| Claim | Regulated? | Meaning |
|---|---|---|
| カロリーゼロ / ノンカロリー | ✅ | < 5 kcal per 100 g/ml |
| 低カロリー | ✅ | ≤ 40 kcal per 100 g (≤ 20 per 100 ml) |
| 糖類ゼロ / 無糖 | ✅ | Sugars < 0.5 g per 100 g/ml |
| 低糖 | ✅ | Sugars ≤ 5 g per 100 g (≤ 2.5 per 100 ml) |
| 糖類無添加 / 砂糖不使用 | ✅ | No sugars added. **Natural sugars may still be present.** |
| 無脂肪 / ノンファット | ✅ | Fat < 0.5 g per 100 g/ml |
| 食塩無添加 | ✅ | No sodium salts added (the only case where a sodium line may appear) |
| **糖質オフ / 糖質ゼロ / 低糖質** | ❌ **No legal threshold** | Marketing. Show it as "unregulated". |
| ○%カット / オフ (for regulated nutrients) | ✅ | ≥ 25% less than a comparison product, which must be named |

---

## 7. Sanity checks the UI can surface

| Check | If it fails |
|---|---|
| `糖質 + 食物繊維 ≈ 炭水化物` (±~1 g) | Likely an OCR misread. Ask the user to confirm. |
| `糖類 ≤ 糖質 ≤ 炭水化物` and `飽和脂肪酸 ≤ 脂質` | Likely an OCR misread |
| `kcal ≈ P×4 + F×9 + 糖質×4 + fibre×2` (or `+ 炭水化物×4` if there's no fibre line), within ±20% | Possibly a misread. If kcal is **lower** and 糖質 ≫ 糖類, it's probably sugar alcohols, not an error. |
| Salt in a plausible range (< 30 g per 100 g) | A lost decimal point |

---

## 8. Copy and terminology for UI

| Use | Avoid | Why |
|---|---|---|
| Net carbs | Sugar, sugars, carbs (for 糖質) | 糖質 includes starch and sugar alcohols |
| Sugars | Added sugar | 糖類 includes natural sugars |
| Carbohydrate (includes fibre) | Carbs (ambiguous) | US and EU conventions differ |
| Not disclosed / not listed | 0, —, N/A | Absence on the label is not zero |
| Under 5 kcal | 0 kcal (when scaled) | "0" is a threshold |
| ≈ 236 mg sodium | 236 mg sodium | Derived from rounded salt |
| Estimated values | Unverified / inaccurate | 推定値 is legal and normal |
| Salt | Sodium (for 食塩相当量) | Different quantities, ×2.54 apart |

Show the Japanese term next to the English one where space allows (e.g. "Net carbs 糖質"). Users will see these characters on packs and learn to recognise them.

Information states, used in the prototype:
- ✓ **Stated**: printed on the label
- → **Worked out**: derived from what's printed (sodium, %DV, other net carbs, ranges)
- ? **Not disclosed or uncertain**: missing lines, zero thresholds, estimates, unregulated claims

---

## 9. Sample data for mocks

All products are invented, and the values are internally consistent. Each one exercises a different state; use them in mocks instead of lorem ipsum.

```json
[
  {
    "id": "chips", "name": "Potato chips", "jpName": "ポテトチップス",
    "carbState": "A", "layout": "inline", "estimate": true,
    "basis": { "label": "1袋（60g）当たり", "amount": 60, "unit": "g" },
    "pack": { "amount": 60, "unit": "g" },
    "n": { "energy": 336, "protein": 3.1, "fat": 21.6, "carbs": 32.4, "salt": 0.6 }
  },
  {
    "id": "tea", "name": "Bottled milk tea", "jpName": "ミルクティー",
    "carbState": "B",
    "basis": { "label": "100ml当たり", "amount": 100, "unit": "ml" },
    "pack": { "amount": 500, "unit": "ml" },
    "n": { "energy": 37, "protein": 0.7, "fat": 0.6, "carbs": 7.2, "sugars": 7.0, "salt": 0.08 }
  },
  {
    "id": "granola", "name": "Fruit granola", "jpName": "フルーツグラノーラ",
    "carbState": "D",
    "basis": { "label": "1食分（50g）当たり", "amount": 50, "unit": "g" },
    "pack": { "amount": 400, "unit": "g" },
    "n": { "energy": 220, "protein": 4.3, "fat": 7.6, "sat": 2.9, "carbs": 36.0,
           "netCarbs": 32.1, "sugars": 11.2, "fiber": 3.9, "salt": 0.2 }
  },
  {
    "id": "choco", "name": "Low-carb chocolate", "jpName": "糖質オフチョコ",
    "carbState": "D", "claim": "糖質オフ",
    "basis": { "label": "1枚（25g）当たり", "amount": 25, "unit": "g" },
    "pack": { "amount": 75, "unit": "g" },
    "n": { "energy": 116, "protein": 2.3, "fat": 9.1, "sat": 5.6, "carbs": 11.3,
           "netCarbs": 6.4, "sugars": 0.9, "fiber": 4.9, "salt": 0.03 },
    "note": "kcal is below the 4/9/4 estimate (126) because of sugar alcohols"
  },
  {
    "id": "soda", "name": "Zero-calorie cola", "jpName": "ゼロコーラ",
    "carbState": "A", "claim": "カロリーゼロ", "groupedZeros": ["protein", "fat"],
    "basis": { "label": "100ml当たり", "amount": 100, "unit": "ml" },
    "pack": { "amount": 500, "unit": "ml" },
    "n": { "energy": 0, "protein": 0, "fat": 0, "carbs": 0.9, "salt": 0.02 },
    "note": "0 kcal per 100 ml means up to 25 kcal per bottle"
  }
]
```

There's no state-C example above. For one, take the granola and drop `sugars`.

**Edge cases a design should also cover:**
- No nutrition panel at all. This is legal for packages ≤ 30 cm², alcohol, tea and spices, and very small producers. Treat it as an empty state, not an error.
- Two panels: as sold and as prepared (e.g. dry noodles and cooked noodles).
- Values given as a range (`熱量 120〜150kcal`)
- Extra items printed outside the box (caffeine, functional ingredients). Show them as "Other", separate from the standard nutrients.
- Health-claim foods (機能性表示食品, 栄養機能食品), which are labelled per daily intake (一日当たり).
- A sodium line (`ナトリウム 120mg（食塩相当量 0.3g）`), which only appears when no sodium salts were added

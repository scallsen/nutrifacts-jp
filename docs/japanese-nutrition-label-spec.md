# Japanese Nutrition Facts Labels (栄養成分表示): Reference for the Parser

Researched 2026-10-16. Rules come from the Food Labeling Act (食品表示法) and the Food Labeling Standards (食品表示基準), which the Consumer Affairs Agency (消費者庁, CAA) maintains. The values below include the **2025 revision**, which took effect 2025-04-01 and has a transition period until 2028-03-31.

---

## 1. What must be on the label

Nutrition labeling has been mandatory for all consumer-facing packaged processed foods since April 2020, when the 5-year transition ended.

| Status | Nutrients |
|---|---|
| **Mandatory (義務)** | 熱量 (energy), たんぱく質 (protein), 脂質 (fat), 炭水化物 (carbohydrate), 食塩相当量 (salt equivalent) |
| **Recommended (推奨)** | 飽和脂肪酸 (saturated fat), 食物繊維 (dietary fibre) |
| **Optional (任意)** | 糖質 (available carbohydrate / "net carbs"), 糖類 (sugars), n-3系脂肪酸, n-6系脂肪酸, コレステロール, vitamins, minerals, ナトリウム (sodium, only in limited cases, see §4) |

### Exempt products (they may have no panel at all)
- Packages whose printable area is roughly **≤ 30 cm²**
- Alcoholic drinks (酒類)
- Foods that contribute almost nothing nutritionally: all five mandatory values qualify for "0", or trivial daily intake (coffee beans, tea leaves, herbs, spices)
- Recipes that change within 3 days (daily bento)
- Very small businesses (consumption-tax-exempt, or roughly ≤ 20 employees, ≤ 5 in retail/services)
- Food sold where it was made (bakery, in-store deli)

**App implication:** "no nutrition panel found" is a legitimate result, not just an OCR failure.

---

## 2. Layout

### Fixed order. Manufacturers may not reorder it.

Minimal format (別記様式2):
```
栄養成分表示
（100g当たり）          ← the unit; see §3
熱量          ○○kcal
たんぱく質      ○○g
脂質           ○○g
炭水化物        ○○g
食塩相当量      ○○g
```

Full format (別記様式3); rows that aren't used are omitted:
```
栄養成分表示
（1袋 45g当たり）
熱量            kcal
たんぱく質        g
脂質             g
 －飽和脂肪酸      g
 －n-3系脂肪酸     g
 －n-6系脂肪酸     g
コレステロール     mg
炭水化物          g
 －糖質           g
  －糖類          g     ← sub-item of 糖質
 －食物繊維        g
食塩相当量        g
(vitamins / minerals)  mg / µg
```

The indent or "－" means **"of which"**. The hierarchy is the core of the data model:

```
脂質 ⊃ 飽和脂肪酸, n-3, n-6
炭水化物 = 糖質 + 食物繊維
            糖質 ⊃ 糖類
```

### Allowed variants the parser must handle
1. **No border box.** The frame can be dropped if it's impractical.
2. **Horizontal / inline**, with sub-items in parentheses:
   `栄養成分表示（1本当たり）／熱量 85kcal、たんぱく質 0g、脂質 0g、炭水化物 21.2g（糖質 21.2g、食物繊維 0g）、食塩相当量 0.1g`
   Separators seen: `／` `/` `、` `,` `:` `：` and line breaks.
3. **Split layout:** columns, or minerals and vitamins in a second block.
4. **Grouped zeros:** `たんぱく質、脂質 0g` assigns 0 to *both* nutrients.
5. **Extra nutrients outside the frame.** Things that aren't in the official list (caffeine, polyphenols, collagen, FOSHU / 機能性表示食品 "functional ingredients") must be printed *outside* the box. Treat them as "other" and don't mix them with the standard nutrients.
6. **Ranges:** a value can be shown as a lower–upper range, e.g. `熱量 120〜150kcal`.

### Allowed alternate names (normalise these)
| Canonical | Also allowed |
|---|---|
| 熱量 | エネルギー |
| たんぱく質 | 蛋白質, たん白質, タンパク質, たんぱく, タンパク |
| Minerals | Element symbols: Ca, Fe, Na, … |
| Vitamins | V.A, VA, ビタミンA, … |
| Units | キロカロリー, グラム, ミリグラム, マイクログラム (IU is **not** allowed) |

### Character-level gotchas for OCR
- Full-width digits and letters: `０-９`, `ｇ`, `ｋｃａｌ`, `．` (full-width period)
- Unit glyphs: `㎎`, `㎍`, `µg` vs `μg` (micro sign vs Greek mu), `Kcal`, `kcal`
- Sodium is in mg, but switches to **g at ≥ 1000 mg**
- Range tildes: `〜` `～` `~` `-`
- Annotations next to the panel: `推定値`, `この表示値は、目安です。`, `日本食品標準成分表2020年版（八訂）の計算による推定値`, `サンプル品分析による推定値`

---

## 3. The "per what?" unit (食品単位)

It always follows the `栄養成分表示` heading. Manufacturers choose one of:

| Form | Example |
|---|---|
| Per 100 g | `100g当たり` |
| Per 100 ml (drinks) | `100ml当たり` |
| Per serving, **must include the amount** | `1食分（30g）当たり`, `1食（標準80g）当たり` |
| Per package | `1包装当たり`, `1袋当たり`, `1本（500ml）当たり` |
| Per other unit | `1個（25g）当たり`, `1枚当たり`, `1粒当たり` |

Things to know:
- **There is no standard serving size.** Each manufacturer sets it, so two similar products may not be comparable unless you normalise to per-100 g.
- To normalise you need the weight. It's usually in the unit string; if not, it's in **内容量** (net contents) on the main label. Read that too.
- Values describe the food **as sold**. Powdered soup and juice are labelled as powder, not as prepared. Rice, dry noodles and similar foods may *additionally* show a cooked-state panel. Expect two panels.
- Foods with nutrient-function claims (栄養機能食品) or functional claims (機能性表示食品) must label **per recommended daily intake** (一日当たりの摂取目安量当たり).

---

## 4. Salt equivalent vs sodium

Japan labels **salt (NaCl) equivalent in grams**, not sodium.

```
食塩相当量 (g) = ナトリウム (mg) × 2.54 ÷ 1000
ナトリウム (mg) = 食塩相当量 (g) × 1000 ÷ 2.54   ≈ g × 393.7
```
(2.54 ≈ 58.44 / 22.99, the molar mass ratio of NaCl to Na.)

- Showing sodium is **forbidden** when sodium salts were added. Only foods with no added sodium salts may show it, and then it has to look like:
  `ナトリウム 120mg（食塩相当量 0.3g）`
- Salt equivalent shows **1 decimal place** (e.g. `0.4g`).

---

## 5. The carbs / sugars / fibre confusion, explained

| Japanese term | What it is | How it's determined | Western equivalent |
|---|---|---|---|
| **炭水化物** (carbohydrate) | Everything that isn't protein, fat, ash or water. **Includes fibre.** | **By difference**: food mass − (protein + fat + ash + water) | US "Total Carbohydrate" (includes fibre) |
| **糖質** (saccharides / available carb) | 炭水化物 **minus fibre**: starch, sugars, oligosaccharides, **sugar alcohols** and other leftovers | **By difference**: food mass − (protein + fat + fibre + ash + water) | EU "Carbohydrate"; roughly "net carbs" |
| **糖類** (sugars) | Monosaccharides and disaccharides only (glucose, fructose, sucrose, lactose, maltose). **Excludes sugar alcohols.** | Measured directly (GC / HPLC) | US/EU "Sugars" / "Total Sugars" (not "Added Sugars") |
| **食物繊維** (dietary fibre) | Fibre | Measured (Prosky method / HPLC) | Dietary fibre |

### The rules that cause the confusion
1. **炭水化物 = 糖質 + 食物繊維.** By definition, not approximately. Because 糖質 is itself computed by difference, the identity holds before rounding.
2. **If either 糖質 or 食物繊維 is shown, both must be shown.** You'll never see 糖質 without 食物繊維 next to it, or the reverse.
3. **糖類 can appear alone** under 炭水化物 (e.g. `炭水化物 30g ／ －糖類 12g`) without a 糖質/fibre split. When 糖質 is present, 糖類 sits *under* 糖質.
4. **Most labels show only 炭水化物.** Fibre is "recommended", not required, so on many products you **cannot** know the fibre or net carbs. The app should say "includes fibre; amount not disclosed" and not guess.
5. **"Low-carb" products** (糖質オフ, 糖質ゼロ) often contain sugar alcohols such as erythritol or maltitol. Those count in **糖質** but **not in 糖類**, so a product can show `糖質 10g` and `糖類 0g`.
6. Because carbohydrate is "whatever's left", it also absorbs organic acids, any leftover alcohol, and measurement error.

### Sanity checks the parser can run
```
糖類 ≤ 糖質 ≤ 炭水化物
|糖質 + 食物繊維 − 炭水化物| ≤ rounding slack (~1 g, more at 1-decimal precision)
飽和脂肪酸 ≤ 脂質
食塩相当量 ≈ ナトリウム × 2.54 / 1000 (when both present)
```
If one of these fails, it's probably an OCR misread, such as a lost decimal point or the wrong row.

---

## 6. How energy (熱量) is calculated

Method: the **modified Atwater method** (修正アトウォーター法), using these factors:

| Component | kcal/g |
|---|---|
| たんぱく質 (protein) | 4 |
| 脂質 (fat) | 9 |
| 糖質 (available carb) | 4 |
| 食物繊維 (fibre) | **2** |
| Alcohol | 7 |
| Organic acids | 3 |
| Sugar alcohols: erythritol | **0** |
| Sorbitol | 3 |
| Mannitol | 2 |
| Maltitol | 2.1 |
| Reduced starch syrup (還元水あめ) | 3.0 |
| Other sugar alcohols | 2.4 |

Formulas:
```
When fibre is known:      kcal ≈ P×4 + F×9 + 糖質×4 + 食物繊維×2
When only 炭水化物 is known: kcal ≈ P×4 + F×9 + 炭水化物×4
```

Gotchas:
- The **Japanese Food Composition Tables 2020 (八訂)** compute "エネルギー" a different way: amino-acid protein ×4, fatty-acid TAG ×9, available carb (monosaccharide equivalent) ×3.75, fibre ×2. That gives slightly different numbers from food-label 熱量. **Don't compare a label against the composition tables and expect an exact match.**
- Use the formula as a **plausibility check (±20%)**, not as ground truth. It will under- or over-shoot on sugar-alcohol products and on products labelled with estimates.

---

## 7. Precision, rounding and "0"

### Minimum display digit
| Display to | Nutrients |
|---|---|
| Whole number (1の位) | 熱量, たんぱく質, 脂質, 飽和脂肪酸, 炭水化物, 糖質, 糖類, 食物繊維, コレステロール, ナトリウム, most minerals and vitamins |
| 1 decimal place | 食塩相当量, n-3 / n-6, 亜鉛, 鉄, 銅, B1, B2, B6, B12, D, E, パントテン酸, マンガン |

- Showing **more** decimals is allowed (`3.75g` and `3.8g` are both fine). The next digit is rounded half up.
- If a value is below the minimum digit but **not** low enough to be called zero, the label must show at least 1 significant figure (e.g. `0.4g`, `0.013g`). It may not show `0`.
- **Expect mixed precision on one label.** Parse as decimals; don't assume integers.

### When "0" is allowed (per 100 g or per 100 ml, whatever the label's unit)
| Nutrient | "0" allowed if below |
|---|---|
| 熱量 | 5 kcal |
| たんぱく質, 脂質, 炭水化物, 糖質, 糖類 | 0.5 g |
| 食物繊維 | 0.5 g (new in 2025) |
| 飽和脂肪酸 | 0.1 g |
| コレステロール | 5 mg |
| ナトリウム | 5 mg (→ 食塩相当量 shown as `0`, `0.0` or `0g`) |

**"0" does not mean none.** A 500 ml bottle that says "0 kcal per 100 ml" can contain up to ~24 kcal per bottle.

### Tolerance: how accurate the numbers are
- 熱量, たんぱく質, 脂質, 炭水化物, 糖質, 糖類, 食物繊維, 飽和脂肪酸, ナトリウム: **±20%**
- Low-content cases (per 100 g/ml): energy < 25 kcal → ±5 kcal; protein / fat / carb / 糖質 / 糖類 / fibre < 2.5 g → ±0.5 g; saturated fat < 0.5 g → ±0.1 g; sodium < 25 mg → ±5 mg
- Minerals and some vitamins: −20% to +50%; B vitamins, C, folate and similar: −20% to +80%
- **推定値 / この表示値は、目安です。** The value is an *estimate* (calculated from ingredient tables or a sample analysis) and the ±20% doesn't apply. This is very common. Capture it as an `isEstimate` flag. Products that make nutrient claims or are health-claim foods may **not** use estimates.

---

## 8. Daily values: Japan doesn't print %DV, but you can compute it

Labels don't show "% Daily Value". The official reference values (**栄養素等表示基準値**) exist for health-claim foods and can be used to compute %DV. They're for **adults 18+ at 2,200 kcal**.

**2025 values** (based on the Dietary Reference Intakes for Japanese, 2025 edition; mandatory for products made from 2028-04-01; 2015 values in brackets):

| Nutrient | 2025 value | (2015) |
|---|---|---|
| 熱量 | 2,200 kcal | 2,200 |
| たんぱく質 | 85 g | 81 |
| 脂質 | 70 g | 62 |
| 飽和脂肪酸 | 17 g | 16 |
| n-3系脂肪酸 | 2.0 g | 2.0 |
| n-6系脂肪酸 | 10.0 g | 9.0 |
| 炭水化物 | 320 g | 320 |
| 食物繊維 | 20 g | 19 |
| ナトリウム | 2,700 mg | 2,900 |
| 食塩相当量 | **7.0 g** (newly listed) | (≈7.5) |
| カリウム | 2,800 mg | |
| カルシウム | 700 mg | |
| 鉄 | 6.5 mg | |
| 亜鉛 | 8.5 mg | |
| マグネシウム | 320 mg | |
| ビタミンA | 770 µg | |
| ビタミンB1 / B2 / B6 / B12 | 1.0 mg / 1.4 mg / 1.3 mg / 4.0 µg | |
| ビタミンC | 100 mg | |
| ビタミンD | 9.0 µg | (5.5) |
| ビタミンE / K | 6.5 mg / 150 µg | |
| 葉酸 | 240 µg | |
| ナイアシン | 13 mg | |

The full list also includes Cr 10 µg, Se 28 µg, Cu 0.8 mg, Mn 3.2 mg, Mo 25 µg, I 140 µg, P 900 mg, pantothenic acid 5.5 mg and biotin 50 µg.

**There's no reference value for 糖質 or 糖類.** If you want a sugar %DV you have to pick a standard yourself (e.g. WHO free sugars < 50 g/day). Note that 糖類 is *total* sugars, including those naturally in fruit and milk, not *added* sugars. Japan has no "added sugars" line.

---

## 9. Claim words on the front of the pack (useful to cross-check)

Thresholds are per 100 g (drinks: per 100 ml, in brackets).

| Nutrient | "None" 無/ゼロ/ノン/レス | "Low" 低/控えめ/ライト | "Reduced" ○%カット/オフ |
|---|---|---|---|
| 熱量 | < 5 kcal (5) | ≤ 40 kcal (20) | ≥ 40 kcal (20) less **and** ≥ 25% relative |
| 脂質 | < 0.5 g (0.5) | ≤ 3 g (1.5) | ≥ 3 g (1.5) less, ≥ 25% |
| 飽和脂肪酸 | < 0.1 g (0.1) | ≤ 1.5 g (0.75) | ≥ 1.5 g (0.75), ≥ 25% |
| コレステロール | < 5 mg (5) | ≤ 20 mg (10) | ≥ 20 mg (10), ≥ 25% |
| 糖類 | < 0.5 g (0.5) | ≤ 5 g (2.5) | ≥ 5 g (2.5), ≥ 25% |
| ナトリウム | < 5 mg (5) | ≤ 120 mg (120) | ≥ 120 mg (120), ≥ 25% (miso 15%, soy sauce 20%) |

High / source claims: protein high ≥ 17.0 g (8.5) per 100 g, source ≥ 8.5 g (4.3); fibre high ≥ 6 g (3), source ≥ 3 g (1.5).

- **糖質 has no official claim thresholds.** 糖質ゼロ and 糖質オフ aren't defined by the 食品表示基準 the way 糖類ゼロ is. Treat 糖質 claims as marketing.
- **糖類無添加 / 砂糖不使用** ("no added sugar") is a different claim. It means no sugars or sugar substitutes were added. The product can still contain natural sugars, and it must then show 糖類 on the panel.
- **食塩無添加** means no sodium salts were added. That is the case where the sodium row is allowed.

---

## 10. Worked example

```
栄養成分表示 1袋(45g)当たり
熱量 230kcal
たんぱく質 3.2g
脂質 12.5g
 －飽和脂肪酸 4.1g
炭水化物 28.0g
 －糖質 26.1g
  －糖類 9.8g
 －食物繊維 1.9g
食塩相当量 0.5g
推定値
```
Derived values:
- Per 100 g: ×(100/45) → 511 kcal, 糖質 58.0 g, …
- Net carbs = 糖質 = 26.1 g. Sugars 9.8 g; non-sugar 糖質 (starch etc.) = 16.3 g
- Sodium ≈ 0.5 × 393.7 ≈ **197 mg** (but the 0.5 is rounded, so the real value is ~157–236 mg)
- Atwater check: 3.2×4 + 12.5×9 + 26.1×4 + 1.9×2 = 233.5 kcal ≈ 230 ✓
- %DV (2025): energy 10.5%, fat 17.9%, sat fat 24.1%, carb 8.8%, fibre 9.5%, salt 7.1%
- `isEstimate = true`

---

## 11. Suggested data model

```ts
type Amount = {
  value: number | null;       // null if not printed
  min?: number; max?: number;  // for ranges "120〜150"
  unit: 'kcal' | 'g' | 'mg' | 'µg';
  raw: string;                 // original OCR text, for debugging
};

type JpNutritionPanel = {
  basis: {
    kind: 'per100g' | 'per100ml' | 'serving' | 'package' | 'unit' | 'dailyIntake';
    label: string;             // "1袋(45g)当たり"
    grams?: number; ml?: number;
  };
  energy: Amount;              // 熱量
  protein: Amount;             // たんぱく質
  fat: Amount & {
    saturated?: Amount; n3?: Amount; n6?: Amount;
  };
  cholesterol?: Amount;
  carbohydrate: Amount & {     // 炭水化物 (includes fibre)
    availableCarb?: Amount & { sugars?: Amount };  // 糖質 ⊃ 糖類
    sugars?: Amount;           // 糖類 when shown directly under 炭水化物
    fiber?: Amount;            // 食物繊維
  };
  saltEquivalent: Amount;      // 食塩相当量 (g)
  sodium?: Amount;             // only if no added sodium salts
  micronutrients: Record<string, Amount>;
  extraOutsidePanel: Record<string, Amount>;   // caffeine, functional ingredients
  isEstimate: boolean;         // 推定値 / 目安
  estimateSource?: string;     // e.g. "日本食品標準成分表2020年版（八訂）"
  referenceStandard?: '2015' | '2025';  // "栄養素等表示基準値(2025)" if printed
};
```

---

## Sources
- Tokyo Metropolitan Govt, *栄養成分表示ハンドブック*, ch. 6: https://www.hokeniryo1.metro.tokyo.lg.jp/shokuhin/hyouji/kyouzai/files/tebiki_chapter6_eiyouseibunhyouji.pdf
- Tokyo Metropolitan Govt, 2025 revision insert (別表第9, 10, 12, 13; applies from 2025-03-28): https://www.hokeniryo1.metro.tokyo.lg.jp/shokuhin/hyouji/kyouzai/files/eiyouseibun_kaitei.pdf
- CAA, *食品表示法に基づく栄養成分表示のためのガイドライン 第2版* (2018): https://www.cao.go.jp/consumer/history/05/kabusoshiki/syokuhinhyouji/doc/180830_sankou4.pdf
- CAA notice on the 栄養素等表示基準値 revision: https://www.caa.go.jp/notice/entry/040562/
- Energy factors for food labels vs the 2020 composition tables: https://www.y-shinno.com/fc2020-calorie-foodlabel/
- MEXT, 日本食品標準成分表2020年版（八訂） carbohydrate volume: https://www.mext.go.jp/content/20201225-mxt_kagsei-mext_01110_041.pdf

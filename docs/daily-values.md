# Daily Values: Sources and Versions

[`data/daily-values.json`](../data/daily-values.json) is the source of truth for every % the app shows. This doc explains where each number came from, which version it is, and how each standard maps onto a Japanese label.

All values were copied from first-party government sources on **2026-10-16**. Don't edit a value without updating its `version` block and the table below.

## Sources at a glance

| Key | Standard | Version to show the user | Basis | Official source |
|---|---|---|---|---|
| `jp` (default) | 栄養素等表示基準値, Consumer Affairs Agency | **2025 revision** (令和7年内閣府令第26号, in force 2025-03-28) | Adults 18+, 2,200 kcal | [e-Gov: 食品表示基準 別表第十](https://laws.e-gov.go.jp/law/427M60000002010) |
| `eu` | EU Reference Intakes | **Regulation (EU) No 1169/2011, Annex XIII** (unchanged since 2011; checked against the 2025-04-01 consolidated text) | Average adult, 8,400 kJ / 2,000 kcal | [EUR-Lex](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:02011R1169-20250401) |
| `us` | FDA Daily Values | **21 CFR 101.9** (last amended 2023-05-24; eCFR up to date as of 2026-10-14) | Adults and children 4+, 2,000 kcal | [eCFR § 101.9](https://www.ecfr.gov/current/title-21/chapter-I/subchapter-B/part-101/subpart-A/section-101.9) |
| `ca` | Health Canada Table of Daily Values | **2022-10-20 version** | Children 4+ and adults | [canada.ca](https://www.canada.ca/en/health-canada/services/technical-documents-labelling-requirements/table-daily-values/nutrition-labelling.html) |
| `who` (fallback) | WHO healthy diet guidelines | **Sugars 2015, sodium 2012, fats 2023, carbohydrate 2023** | Adults; scaled to the chosen source's energy | [WHO Healthy diet fact sheet](https://www.who.int/news-room/fact-sheets/detail/healthy-diet) |

Each source in the JSON has a `version.displayName`. **Show it to the user wherever a % appears** (e.g. in the table footer or Settings), so they know which version the numbers come from.

## Lookup order: WHO fills the gaps

The user picks one source (Japan by default). For each label line:

1. Use the chosen source's value.
2. If its `match` is `none`, use the **WHO** value (`fallbackSource`) and mark the row, e.g. "28% · WHO".
3. If WHO has none either, show **No reference**.

WHO values are **limits** (sugars, fats, sodium) or **targets** (fibre, potassium), not reference amounts. The `kind` field says which, so the copy reads "of the WHO daily limit". Where WHO gives a share of energy, convert it with the chosen source's `referenceEnergyKcal`, or 2,000 kcal when it has none:

| WHO guideline | At 2,000 kcal | At 2,200 kcal (Japan) |
|---|---|---|
| Free sugars < 10% of energy | 50 g | 55 g |
| Saturated fat ≤ 10% of energy | 22.2 g | 24.4 g |
| Total fat ≤ 30% of energy | 66.7 g | 73.3 g |
| Sodium < 2,000 mg | 2,000 mg (≈ 5.1 g salt) | same |
| Fibre ≥ 25 g | 25 g | same |
| Potassium ≥ 3,510 mg | 3,510 mg | same |

The gaps WHO fills for each source:

| Chosen source | Filled by WHO |
|---|---|
| Japan | Sugars (55 g limit) |
| EU | Fibre (25 g target) |
| US | Sugars (50 g limit) |
| Canada | Nothing. Its gaps (energy, protein, carbohydrate) have no single WHO value. |

**WHO limits free sugars, but 糖類 is total sugars** (including sugars naturally in milk and fruit), so the WHO sugars % can come out high. Footnote it, especially for dairy and fruit products.

## Values per Japanese label line

| Label line | 🇯🇵 Japan | 🇪🇺 EU | 🇺🇸 US | 🇨🇦 Canada |
|---|---|---|---|---|
| 熱量 Energy | 2,200 kcal | 2,000 kcal | none ¹ | none |
| たんぱく質 Protein | 85 g | 50 g | 50 g | none |
| 脂質 Fat | 70 g | 70 g | 78 g | 75 g |
| 飽和脂肪酸 Saturated fat | 17 g | 20 g | 20 g | 20 g ≈ ² |
| 炭水化物 Carbohydrate | 320 g | 260 g, fallback only ³ | 275 g | none |
| 糖質 Net carbs | none | 260 g ³ | none | none |
| 糖類 Sugars | none | 90 g | none ⁴ | 100 g |
| 食物繊維 Fibre | 20 g | none | 28 g | 28 g |
| 食塩相当量 Salt | 7.0 g | 6 g ≈ ⁵ | sodium 2,300 mg ⁶ | sodium 2,300 mg ⁶ |
| カリウム Potassium | 2,800 mg | 2,000 mg | 4,700 mg | 3,400 mg |
| カルシウム Calcium | 700 mg | 800 mg | 1,300 mg | 1,300 mg |
| 鉄 Iron | 6.5 mg | 14 mg | 18 mg | 18 mg |
| ビタミンD Vitamin D | 9.0 µg | 5 µg | 20 µg | 20 µg |

"none" means show **No reference**, never a %.

1. The US has no DV for calories. 2,000 kcal is the reference intake the other DVs are based on. If the UI shows % of energy, label it "of 2,000 kcal".
2. Canada's value covers saturated **plus trans** fat. Japanese labels only give saturated fat.
3. EU "carbohydrate" excludes fibre and includes polyols, which is exactly 糖質. Compare 糖質 with 260 g. If the label has no 糖質 line, compare 炭水化物 instead and footnote that the % is slightly high.
4. The US sugar DV (50 g) is for **added** sugars. 糖類 is total sugars, so there's nothing to compare.
5. The EU calculates salt as sodium × 2.5; Japan uses × 2.54. They're about 1.6% apart, so compare directly.
6. Convert first: sodium mg = salt g × 1000 ÷ 2.54. 2,300 mg is about 5.84 g salt.

Japan's table also covers n-3/n-6 fatty acids and 20 more vitamins and minerals. They're in `otherValues`. The other sources only have the four common minerals and vitamins so far.

## The `match` field

Every entry in `dailyValues` says how well the standard fits the Japanese line:

| `match` | Meaning | UI |
|---|---|---|
| `exact` | Same definition | Show the % |
| `approximate` | Slightly different definition | Show the % with a footnote |
| `converted` | Value is for a related quantity (sodium) | Convert the label value, then show the % |
| `fallback` | Use only when the preferred line is missing (`fallbackFor`) | Show the % with a footnote |
| `none` | No value | Show "No reference" |

## Interpretation bands

Some standards also say what counts as "a little" or "a lot" of a % DV. They're stored as `interpretation`:

| Source | Low | High | Notes |
|---|---|---|---|
| Japan | — | — | No official bands |
| EU | — | — | No official bands. UK traffic lights are UK guidance, not EU law. |
| US | ≤ 5% | ≥ 20% | Per serving ([FDA](https://www.fda.gov/food/nutrition-facts-label/how-understand-and-use-nutrition-facts-label)) |
| Canada | ≤ 5% | ≥ 15% | Per serving ([Health Canada](https://www.canada.ca/en/health-canada/services/understanding-food-labels/percent-daily-value.html)) |

## Japan: the old values are still on shelves

Japan's 2025 revision has a transition period until **2028-03-31**. Packs printed before then may state a % using the **2015** values. Those changed values are in `jp.previousVersion`:

| | 2015 | 2025 |
|---|---|---|
| Protein | 81 g | 85 g |
| Fat | 62 g | 70 g |
| Saturated fat | 16 g | 17 g |
| Fibre | 19 g | 20 g |
| Sodium | 2,900 mg | 2,700 mg (salt 7.0 g) |
| Calcium | 680 mg | 700 mg |
| Iron | 6.8 mg | 6.5 mg |
| Vitamin D | 5.5 µg | 9.0 µg |

The app always calculates with the current values. If a label prints its own %, it may not match ours, and that's expected.

## How each value was verified

- **Japan:** Table 10 was read from the consolidated text in the e-Gov law database API (revision `427M60000002010_20261001_508M60000002089`, in force 2026-10-01). It was then cross-checked against the new column of the CAA's comparison table for 令和7年内閣府令第26号. The 2026 amendment didn't change Table 10.
- **EU:** Annex XIII Parts A and B were read from the 2025-04-01 consolidated text and the original 2011 Official Journal text, both from the EU Publications Office. They're identical. The definitions of carbohydrate, sugars, fibre and salt come from Annex I of the same regulation.
- **US:** § 101.9(c)(9) (DRVs) and (c)(8)(iv) (RDIs) were read from the eCFR renderer API. The amendment dates come from the eCFR versioner API.
- **Canada:** the Table of Daily Values page on canada.ca, published 2022-10-20. canada.ca couldn't be downloaded directly, so it was read through a summarising fetch. Worth a visual re-check.
- **WHO:** the Healthy diet fact sheet (updated 2026-01-26), the 2023 fats and carbohydrates announcement, the sodium reduction fact sheet and the guideline publication pages, all on who.int.

## Updating

1. Re-check each `urls.values` page. For Japan, also check the CAA's [amendment history](https://www.caa.go.jp/policies/policy/food_labeling/food_labeling_act/past_ordinance/) for changes to 別表第十.
2. If a value changes, move the old one into `previousVersion`, update `version`, and set `retrieved` to the new date.
3. Update the tables in this doc.

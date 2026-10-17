# Health Score

The iPhone app grades a product from its nutrition panel. The rubric is in [`data/health-score.json`](../data/health-score.json); this doc explains it. The thresholds come from official sources. The weights, the 0–100 scale and the grade bands are this app's own product decisions, and the UI should say so ("nutrifacts score v1", not a government grade).

## Who computes what

| Step | Done by | Why |
|---|---|---|
| Read the panel from the screenshot | The chosen backend: Apple Private Cloud Compute, the on-device Apple model, or the ai& backend | Needs vision and Japanese OCR |
| Check the reading (`糖類 ≤ 糖質 ≤ 炭水化物`, Atwater, …) | The app | Same rules as [`ui-domain-context.md` §7](ui-domain-context.md#7-sanity-checks-the-ui-can-surface) |
| Normalise to per 100 g / ml | The app | Only fair basis for comparing products |
| Score and grade | The app, deterministically, from this rubric | The same panel always gets the same grade, whichever backend read it |

The models never invent a score. A model that saw no 糖類 line could easily treat it as 0, which rule 3 forbids.

## The formula

All values are per 100 g, or per 100 ml when the label's basis is in ml (drinks use the `drink` thresholds).

```
score = 100 − Σ penalty(negative) + Σ bonus(positive), clamped to 0…100
```

**Negatives** (fat, saturated fat, sugars, salt): no penalty at or below `low`, the full `weight` at or above `high`, linear in between.

| Nutrient | Weight | Low (solid / drink) | High (solid / drink) |
|---|---|---|---|
| Fat 脂質 | 15 | 3.0 / 1.5 g | 17.5 / 8.75 g |
| Saturated fat 飽和脂肪酸 | 25 | 1.5 / 0.75 g | 5.0 / 2.5 g |
| Sugars 糖類 | 25 | 5.0 / 2.5 g | 22.5 / 11.25 g |
| Salt 食塩相当量 | 25 | 0.3 / 0.3 g | 1.5 / 0.75 g |

**Positives** (protein, fibre): nothing below the "source of" threshold, half the `weight` at it, rising linearly to the full `weight` at the "high in" threshold.

| Nutrient | Weight | Source (solid / drink) | High (solid / drink) |
|---|---|---|---|
| Protein たんぱく質 | 10 | 8.5 / 4.3 g | 17 / 8.5 g |
| Fibre 食物繊維 | 10 | 3 / 1.5 g | 6 / 3 g |

**Grades:** A ≥ 80, B ≥ 65, C ≥ 50, D ≥ 35, E below 35.

Energy isn't scored on its own. There's no official "high" energy threshold, and fat and sugars already carry most of it.

### Sources for the thresholds

- **Low** and **source / high in** (positives): Japan's nutrient-content claim thresholds, 食品表示基準 別表第十二 ([spec §9](japanese-nutrition-label-spec.md#9-claim-words-on-the-front-of-the-pack-useful-to-cross-check)). Japan's low-salt threshold is sodium ≤ 120 mg, which is 0.30 g salt.
- **High** (negatives): UK Department of Health / FSA front-of-pack guidance (2016), the red traffic-light thresholds per 100 g and per 100 ml. Japan defines no "high" level. The UK's per-portion rule isn't used, because Japan has no standard portion.

Re-check both against the official pages before shipping, the same way [`daily-values.md`](daily-values.md) was verified.

## Missing lines make a range, not a guess

A missing line means **not disclosed** (rule 3), so the app scores the best and the worst case the label allows and shows both, e.g. **"B–E · 20–70"**.

| Line | If not disclosed, it can be anywhere in |
|---|---|
| Saturated fat | 0 … fat |
| Sugars | 0 … 糖質, or 0 … 炭水化物 if 糖質 isn't shown |
| Fibre, protein | No bonus. Undisclosed positives earn nothing, and the UI says "not disclosed" rather than "0 g". |

A printed **"0"** means below the zero threshold per 100 g (rule 4), so it's scored as the range 0 … threshold. Every zero threshold is under the matching `low`, so a "0" never costs points. A printed range (`120〜150`) is scored at both ends.

The range is wide on most Japanese labels, because they only carry the five mandatory lines. That is the honest answer: the label doesn't say enough to grade the product more tightly. The UI should name the lines that cause the spread ("Saturated fat and sugars aren't disclosed").

## When there's no score

- **No panel found:** legal for small packs, alcohol, tea and spices. Show an empty state, not an error.
- **Basis without a weight** (`1袋当たり` with no 内容量 visible): the app can't normalise to per 100 g, so it asks the user for the weight before scoring.

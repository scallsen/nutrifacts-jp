# nutrifacts-jp

An app that parses the nutrition facts panel (栄養成分表示) on Japanese food packaging and shows a simplified, honest view of it.

## Read before working

- **UI / design work:** read [`docs/ui-domain-context.md`](docs/ui-domain-context.md) first. It explains what each label line means, what a *missing* line means, the four carbohydrate disclosure states every carb UI must handle, and what copy to use.
- **Parsing, data model, rules:** [`docs/japanese-nutrition-label-spec.md`](docs/japanese-nutrition-label-spec.md) has the regulations, thresholds, formulas and sources.
- **Daily values (%):** [`data/daily-values.json`](data/daily-values.json) is the source of truth for Japan (default), EU, US and Canada, with versions and official sources. [`docs/daily-values.md`](docs/daily-values.md) explains how each one maps onto a Japanese label.
- **Health score:** [`docs/health-score.md`](docs/health-score.md) and [`data/health-score.json`](data/health-score.json). The app computes the score; backends only read the label.
- **iPhone app:** [`ios/README.md`](ios/README.md). Regenerate the Xcode project with `xcodegen generate` after adding files.
- **Reference prototype:** [`prototypes/label-explainer.html`](prototypes/label-explainer.html), a self-contained page with the annotated label, the carb-nesting diagram and the simplified view. Open it in a browser.

## Rules that must never be broken

1. `炭水化物 = 糖質 + 食物繊維`, and `糖類 ⊂ 糖質`. 炭水化物 includes fibre.
2. 糖質 = **net carbs**, not "sugar". 糖類 = **sugars** (natural and added), not "added sugar".
3. A missing line means **not disclosed**, never 0. Most labels show only 炭水化物.
4. "0" on a label means below a threshold per 100 g/ml (e.g. < 5 kcal), not none.
5. 食塩相当量 is **salt**. Sodium mg = salt g × 1000 ÷ 2.54.
6. Always show the basis (per 100 g, per serving, per pack). There's no standard serving size.
7. Take every % from [`data/daily-values.json`](data/daily-values.json). Never hard-code one. Where an entry's `match` is `none` (e.g. 糖質 and 糖類 under Japan's values), show "No reference", not a %. Always show which standard and version the % uses.

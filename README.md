# nutrifacts-jp

Parse Japanese nutrition labels (栄養成分表示) and show them in a simplified, translated view with daily values, sodium in mg, and honest "not disclosed" states.

- [Domain context for UI work](docs/ui-domain-context.md)
- [Label spec: rules, thresholds, formulas](docs/japanese-nutrition-label-spec.md)
- [Daily values: sources and versions](docs/daily-values.md) ([data](data/daily-values.json))
- [Interactive explainer prototype](prototypes/label-explainer.html) ([published](https://claude.ai/artifact/PtqGn8cchaKZ1Q6kmiKJCW))
- [iPhone app](App/README.md): camera → grade, via Apple Private Cloud Compute or [AI&](docs/aiand.md) (through the [Cloudflare Worker](backend/README.md))
- [Health score rubric](docs/health-score.md) ([data](data/health-score.json))
- [Beta sign-up page](website/README.md) ([live](https://scallsen.github.io/nutrifacts-jp/)), deployed to GitHub Pages

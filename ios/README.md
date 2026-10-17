# Nutrifacts for iPhone

Press the Action Button while a Japanese nutrition label is on screen. The app reads the 栄養成分表示 panel and grades it A–E.

```
Action Button → Shortcut: Take Screenshot → Score Nutrition Label (App Intent)
                                             ├─ Vision OCR (on device, ja-JP)
                                             ├─ read the panel: Apple PCC | on-device model | ai&
                                             └─ score in the app: data/health-score.json
```

- **Reading** the label is the backend's job. You choose it in Settings: Apple Private Cloud Compute (default), the on-device Apple model, or the [ai& backend](../docs/backend-api.md).
- **Scoring** always happens in the app, using the rubric in [`docs/health-score.md`](../docs/health-score.md), so the same panel gets the same grade whichever backend read it. Lines the label doesn't disclose turn the grade into a range (e.g. B–E) and are never treated as 0.
- **%DV** comes from [`data/daily-values.json`](../data/daily-values.json). Both JSON files are bundled straight from `data/`; there are no copies.

Runs on iOS 26 and later; build with Xcode 27.

| | iOS 26 | iOS 27 |
|---|---|---|
| Apple Private Cloud Compute | Not available (hidden in Settings) | ✓ default, reads the image + OCR |
| On-device Apple model | ✓ default, reads the OCR text only | ✓ reads the image + OCR when the model supports vision |
| ai& | ✓ | ✓ |

The iOS 27 code is behind `#available(iOS 27, *)` in `AppleIntelligenceReader` and `SettingsView`. A stored PCC choice falls back to on-device on iOS 26 (`Backend.resolved`).

## Build

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated project is committed, so you only need XcodeGen when you add files or change settings.

```bash
cd ios && xcodegen generate && open NutrifactsJP.xcodeproj
```

Run the tests:

```bash
cd ios && xcodebuild test -project NutrifactsJP.xcodeproj -scheme NutrifactsJP -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Signing and Private Cloud Compute

PCC needs the managed entitlement `com.apple.developer.private-cloud-compute`, which is already in `NutrifactsJP/Support/NutrifactsJP.entitlements`.

1. In the Developer portal (Certificates, Identifiers & Profiles → Identifiers), register the App ID `com.justingarcia.NutrifactsJP`. To use a different ID, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` and regenerate.
2. On that App ID, turn on **Private Cloud Compute** under Capability Requests / Additional Capabilities. Your account needs the approved entitlement.
3. In Xcode, pick your team under Signing & Capabilities (or set `DEVELOPMENT_TEAM` in `project.yml`). Automatic signing then fetches a profile that includes the entitlement.

PCC doesn't work in the Simulator, so test it on a device. To test the quota UI, use Product › Scheme › Edit Scheme › Run › Options › "Simulated Apple Foundation Models Availability".

## Action Button setup

Apps can't capture the screen themselves, so the Action Button runs a two-step Shortcut. The app walks through this under **Set up the Action Button**.

1. Shortcuts → **+** → add **Take Screenshot**, then **Score Nutrition Label**. Its Screenshot input connects to the previous action automatically.
2. Settings → Action Button → **Shortcut** → pick it.

To scan a pack in a shop, open the **Camera app**, frame the panel in the viewfinder and press the Action Button. The screenshot of the viewfinder is what gets read, so there's no photo to take or delete. The same press works for a product page or photo on screen.

The result appears as a Shortcuts snippet and is saved to the app's history. When a label's basis has no weight (`1袋当たり`), the snippet says so and the app asks for the weight.

## Layout

| Folder | What's in it |
|---|---|
| `App/` | App entry point and `ScanService`, the screenshot → saved scan pipeline |
| `Intents/` | `ScoreLabelIntent` (Action Button / Shortcuts / Siri) |
| `Extraction/` | Vision OCR, the `@Generable` label schema, the Apple and ai& readers |
| `Model/` | Panel model, %DV lookup, sanity checks, SwiftData `Scan`, sample labels |
| `Scoring/` | `HealthScorer`, the deterministic score with best/worst-case ranges |
| `Views/` | SwiftUI |

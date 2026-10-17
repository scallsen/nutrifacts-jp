# NutriFacts iOS app

SwiftUI, iOS 26+ (Private Cloud Compute needs iOS 27). Open `NutriFacts.xcodeproj` and run on an iPhone simulator.
The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen): run `xcodegen generate` in this folder after adding or removing files.

## What's real and what's placeholder

| Part | State |
|---|---|
| Camera | **Placeholder.** `CameraBackdrop` draws a pack. Swap in `DataScannerViewController`. Until then, real scans come from the Action Button or **Score a Screenshot**. |
| Reading a real label | **Real.** Vision OCR on device, then Apple Private Cloud Compute (iOS 27), the on-device Apple model, or the [ai& backend](../docs/backend-api.md), chosen in Settings. See `Reading/`. |
| Action Button | **Real.** `ScoreLabelIntent`, run by a Shortcut: Take Screenshot → Score Nutrition Label. With the Camera app open, the screenshot is the viewfinder. Setup is in Settings. |
| Health score | **Real.** `Scoring/HealthScore.swift`, using the rubric in [`data/health-score.json`](../data/health-score.json) ([doc](../docs/health-score.md)) and `PanelAnalysis.bounds`, so missing lines make a range. |
| Simulated camera's text recognition | **Placeholder.** `MockLabelScanner` returns the sample label the camera is "pointing at", cycling through `SampleLabels`. |
| Daily values | **Hand-copied** into `ReferenceSource.swift`. Not loaded from `data/daily-values.json` yet. |
| History | **In memory only.** Cleared when the app quits. Action Button scans are added while the app is running. |
| Analysis (%, WHO fallback, levels, warnings, carb states, "0" handling) | Implemented in `PanelAnalysis.swift`. |

## Signing and Private Cloud Compute

The bundle ID is `com.justingarcia.NutrifactsJP` on team `XDWKSAH7W3`, where it's registered with the Private Cloud Compute capability. The managed entitlement is in `NutriFacts/NutriFacts.entitlements`. PCC doesn't run in the Simulator, so test it on a device.

## Flow

1. First launch: welcome sheet, then **Health Guidelines** (Japan pre-selected, searchable by country).
2. Camera with a small sheet. The label is found, then captured automatically after about 3 seconds. The shutter captures straight away.
3. Result sheet at half height over the frozen frame:
   - Things to know (warnings only)
   - Amount picker
   - Nutrition: level word and % in the level colour
   - Carbohydrate breakdown
   - About this label
   - Label photo
4. Scan Again cycles to the next sample label.

Design decisions come from the mock at https://claude.ai/artifact/2QUjq5DayY8kimW7ryX7LC and the docs in `../docs`.

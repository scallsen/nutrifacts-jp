# NutriFacts iOS app (v1, placeholder backend)

SwiftUI, iOS 26+. Open `NutriFacts.xcodeproj` and run on an iPhone simulator.
The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen): run `xcodegen generate` in this folder after adding or removing files.

## What's real and what's placeholder

| Part | State |
|---|---|
| Camera | **Placeholder.** `CameraBackdrop` draws a pack. Swap in `DataScannerViewController`. |
| Text recognition / parsing | **Placeholder.** `MockLabelScanner` returns the sample label the camera is "pointing at", cycling through `SampleLabels`. |
| Daily values | **Hand-copied** into `ReferenceSource.swift`. Not loaded from `data/daily-values.json` yet. |
| History | **In memory only.** Cleared when the app quits. |
| Analysis (%, WHO fallback, levels, warnings, carb states, "0" handling) | Implemented in `PanelAnalysis.swift`. |

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

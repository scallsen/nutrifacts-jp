# NutriFacts iOS app

SwiftUI, iOS 26+ (Private Cloud Compute needs iOS 27). Open `NutriFacts.xcodeproj` and run on an iPhone simulator.
The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen): run `xcodegen generate` in this folder after adding or removing files.

## What's real and what's placeholder

| Part | State |
|---|---|
| Camera | **Real on iPhone.** `Camera/CameraEngine.swift` runs an AVFoundation session. Vision text recognition checks a frame about every 0.5 s, on device, to spot the 栄養成分表示 panel. `LiveScanner` draws brackets around it and takes a full-resolution photo (`AVCapturePhotoOutput`) once it's been steady for 1.5 s, or on the shutter. The photo freezes behind the sheet while it's read. After a failed read it waits for the panel to leave the frame before capturing again. **Simulator:** no camera, so `CameraBackdrop` draws a pack and cycles through the samples. |
| Reading a real label | **Real.** Chosen in Settings. See `Reading/`. **[ai&](../docs/aiand.md)** (the default when the build has a Worker URL) sends the photo to the NutriFacts API ([`backend/`](../backend/), a Cloudflare Worker), which reads it with an AI& vision model; set its URL in `Config/NutriFacts.xcconfig`. **Apple Intelligence** uses Private Cloud Compute (iOS 27, photo only), and falls back to the on-device model when PCC can't run: offline, past the daily limit, on iOS 26 (OCR text only) or without the entitlement. A scan read on device says so on the result. |
| Health score | **Not shown.** The result and History no longer show a grade. `Scoring/HealthScore.swift` and `Views/GradeViews.swift` are kept, using the rubric in [`data/health-score.json`](../data/health-score.json) ([doc](../docs/health-score.md)) and `PanelAnalysis.bounds`, so missing lines make a range. |
| Simulated camera's text recognition | **Placeholder.** `MockLabelScanner` returns the sample label the camera is "pointing at", cycling through `SampleLabels`. |
| Daily values | **Hand-copied** into `ReferenceSource.swift`. Not loaded from `data/daily-values.json` yet. |
| History | **Real.** `Services/ScanStore.swift` saves each scan on the iPhone (Application Support/Scans, one folder per scan with its JSON and photos). Grouped by day, searchable by product name, swipe to delete. |
| Analysis (%, WHO fallback, each authority's own words, warnings, carb states, "0" handling) | Implemented in `PanelAnalysis.swift`. |

## Signing and Private Cloud Compute

The bundle ID is `com.justingarcia.NutrifactsJP` on team `XDWKSAH7W3`, where it's registered with the Private Cloud Compute capability. The managed entitlement is in `NutriFacts/NutriFacts.entitlements`. PCC doesn't run in the Simulator, so test it on a device.

## Flow

1. First launch: welcome sheet, then **Health Guidelines** (Japan pre-selected, searchable by country).
2. Camera with a small sheet. The label is found, then captured automatically after about 3 seconds. The shutter captures straight away.
3. Result sheet at half height over the frozen frame:
   - Things to know (warnings only)
   - Amount picker, opening on the whole pack when 内容量 is known. A label per piece, serving or pack (1個当たり, 1包装当たり) gets a stepper in its own unit, and a pack counted in 内容量 (6個入) gives the whole pack without a weight. With no weight printed, an optional Weight row adds per 100 g and the UK's traffic lights; the FDA and Canada judge a piece without one
   - Ingredients, read from the same photo when the box is in it, or from a box photo taken while looking for the panel
   - Nutrition: level word and % in the level colour
   - Carbohydrate breakdown
   - About this label
   - Label photo
4. New Scan cycles to the next sample label.

Design decisions come from the mock at https://claude.ai/artifact/2QUjq5DayY8kimW7ryX7LC and the docs in `../docs`.

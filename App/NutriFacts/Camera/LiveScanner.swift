import AVFoundation
import SwiftUI
import VisionKit

/// The real camera: VisionKit's live text scanner, watching for a 栄養成分表示 panel.
/// Not available in the Simulator, where the app falls back to `CameraBackdrop`.
@MainActor @Observable
final class LiveScanner {
    enum Access { case unknown, granted, denied }

    /// True on devices that can run the live scanner (not the Simulator).
    static var isSupported: Bool { DataScannerViewController.isSupported }

    private(set) var access: Access = .unknown
    /// Where the panel is on screen, in the scanner view's coordinates. Nil while no panel is in view.
    private(set) var panelRect: CGRect?
    /// Called when a panel comes into or goes out of view.
    var onPanelChange: ((Bool) -> Void)?
    /// Whether the camera should be recognising text right now.
    var isActive = false

    weak var controller: DataScannerViewController?

    func requestAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: access = .granted
        case .notDetermined: access = await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        default: access = .denied
        }
    }

    /// A full-resolution photo of what the camera sees now.
    func capturePhoto() async throws -> UIImage {
        guard let controller else { throw CaptureError.notReady }
        return try await controller.capturePhoto()
    }

    enum CaptureError: LocalizedError {
        case notReady
        var errorDescription: String? { "The camera isn't ready yet." }
    }

    // MARK: Panel detection

    /// Lines that only appear on a nutrition panel. Alternate spellings from the spec are included.
    private static let panelWords = ["栄養成分表示", "栄養成分", "熱量", "エネルギー", "たんぱく質", "蛋白質", "タンパク質",
                                     "脂質", "炭水化物", "食塩相当量", "糖質", "糖類", "食物繊維"]

    func update(with items: [RecognizedItem]) {
        var rect: CGRect?
        var hits = Set<String>()
        for case .text(let text) in items {
            let found = Self.panelWords.filter { text.transcript.contains($0) }
            guard !found.isEmpty else { continue }
            hits.formUnion(found)
            let b = text.bounds
            let box = CGRect(x: min(b.topLeft.x, b.bottomLeft.x), y: min(b.topLeft.y, b.topRight.y),
                             width: max(b.topRight.x, b.bottomRight.x) - min(b.topLeft.x, b.bottomLeft.x),
                             height: max(b.bottomLeft.y, b.bottomRight.y) - min(b.topLeft.y, b.topRight.y))
            rect = rect.map { $0.union(box) } ?? box
        }
        // The heading alone, or three of the mandatory/optional lines, counts as a panel.
        let isPanel = hits.contains("栄養成分表示") || hits.count >= 3
        let newRect = isPanel ? rect : nil
        let changed = (newRect == nil) != (panelRect == nil)
        withAnimation(.snappy) { panelRect = newRect }
        if changed { onPanelChange?(newRect != nil) }
    }

    func clearPanel() {
        let had = panelRect != nil
        panelRect = nil
        if had { onPanelChange?(false) }
    }
}

/// Hosts the DataScannerViewController and starts or stops it with `scanner.isActive`.
struct LiveCameraView: UIViewControllerRepresentable {
    let scanner: LiveScanner

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["ja", "en"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false)
        controller.delegate = context.coordinator
        scanner.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if scanner.isActive, !controller.isScanning {
            try? controller.startScanning()
        } else if !scanner.isActive, controller.isScanning {
            controller.stopScanning()
            scanner.clearPanel()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(scanner: scanner) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let scanner: LiveScanner
        init(scanner: LiveScanner) { self.scanner = scanner }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            scanner.update(with: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            scanner.update(with: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            scanner.update(with: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            scanner.clearPanel()
        }
    }
}

/// The live camera, the brackets around the panel, and the frozen frame once captured.
struct LiveCameraBackdrop: View {
    let scanner: LiveScanner
    let frozenFrame: UIImage?
    let phase: AppModel.Phase

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            switch scanner.access {
            case .granted:
                LiveCameraView(scanner: scanner)
                if let frozenFrame {
                    // Fill the screen like the preview does, without letting the photo resize the stack.
                    Color.clear
                        .overlay { Image(uiImage: frozenFrame).resizable().scaledToFill() }
                        .clipped()
                        .overlay(Color.black.opacity(phase == .result ? 0.35 : 0))
                        .transition(.opacity)
                } else if let rect = scanner.panelRect {
                    CornerBrackets()
                        .stroke(.yellow, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .frame(width: rect.width + 24, height: rect.height + 24)
                        .offset(x: rect.minX - 12, y: rect.minY - 12)
                        .shadow(color: .yellow.opacity(0.5), radius: 6)
                        .allowsHitTesting(false)
                }
            case .denied:
                CameraAccessOff()
            case .unknown:
                EmptyView()
            }
        }
        .animation(.snappy, value: frozenFrame == nil)
    }
}

private struct CameraAccessOff: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text("Camera access is off").font(.headline)
            Text("Turn it on to scan labels, or use Score a Screenshot below.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.glass)
        }
        .foregroundStyle(.white)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 250)
    }
}

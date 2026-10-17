import CoreGraphics
import ImageIO
import SwiftUI

struct Scan: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let panel: LabelPanel
    /// What read the label. Nil for the simulated camera.
    var backend: Backend? = nil
}

extension PresentationDetent {
    static var scanning: PresentationDetent { .height(250) }
}

@MainActor @Observable
final class AppModel {
    /// Shared with the App Intent, so Action Button scans land in the same history.
    static let shared = AppModel()

    enum Phase { case scanning, result }

    var phase: Phase = .scanning
    var detent: PresentationDetent = .scanning
    /// The scanner has locked onto a panel and is waiting for the frame to settle.
    var labelFound = false
    /// What the simulated camera is pointing at.
    private(set) var cameraTarget: LabelPanel
    private(set) var current: Scan?
    /// Placeholder: kept in memory only. The real app stores scans and the cropped photo on device.
    private(set) var history: [Scan] = []
    /// A real scan in progress (screenshot or Action Button).
    private(set) var isReading = false
    /// Why the last real scan failed, shown on the scanning sheet.
    var readError: String?

    private let scanner: any LabelScanning
    private var nextSample = 0
    private var autoCapture: Task<Void, Never>?

    init(scanner: any LabelScanning = MockLabelScanner()) {
        self.scanner = scanner
        cameraTarget = SampleLabels.all[0]
    }

    var availableDetents: Set<PresentationDetent> { phase == .result ? [.medium, .large] : [.scanning] }

    /// Shows the live camera and captures automatically once the panel is steady.
    func startScanning() {
        autoCapture?.cancel()
        labelFound = false
        cameraTarget = SampleLabels.all[nextSample % SampleLabels.all.count]
        nextSample += 1
        phase = .scanning
        detent = .scanning
        autoCapture = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation { self?.labelFound = true }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.capture(fromAutoCapture: true)
        }
    }

    func capture(fromAutoCapture: Bool = false) async {
        if !fromAutoCapture { autoCapture?.cancel() }
        guard phase == .scanning, let panel = try? await scanner.scan(cameraTarget) else { return }
        let scan = Scan(date: .now, panel: panel)
        history.insert(scan, at: 0)
        current = scan
        withAnimation(.snappy) {
            labelFound = false
            phase = .result
            detent = .medium
        }
    }

    func clearHistory() { history.removeAll() }

    /// Reads a screenshot or photo with the backend chosen in Settings and adds it to history.
    func read(imageData: Data, backend: Backend = Backend.selected) async -> Result<Scan, any Error> {
        isReading = true
        readError = nil
        defer { isReading = false }
        do {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImageError.unreadable }
            let ocr = (try? await OCR.text(in: image)) ?? ""
            let label = try await LabelReaders.make(backend).read(image, ocrText: ocr)
            let scan = Scan(date: .now, panel: try label.toPanel(photo: Self.photo(from: source)), backend: backend)
            history.insert(scan, at: 0)
            return .success(scan)
        } catch {
            readError = error.localizedDescription
            return .failure(error)
        }
    }

    /// Reads an image from the app and shows the result sheet.
    func readAndShow(imageData: Data) async {
        autoCapture?.cancel()
        guard case .success(let scan) = await read(imageData: imageData) else { return }
        current = scan
        withAnimation(.snappy) {
            labelFound = false
            phase = .result
            detent = .medium
        }
    }

    enum ImageError: LocalizedError {
        case unreadable
        var errorDescription: String? { "That file isn't an image NutriFacts can read." }
    }

    private static func photo(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 1600,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return AIAndReader.jpeg(image, quality: 0.8)
    }
}

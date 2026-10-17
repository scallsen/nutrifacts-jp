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

    /// The real camera. Nil in the Simulator, which uses the simulated camera instead.
    let liveScanner: LiveScanner?
    /// The captured photo, shown behind the sheet while it's read and on the result.
    private(set) var frozenFrame: UIImage?

    private let scanner: any LabelScanning
    private var nextSample = 0
    private var autoCapture: Task<Void, Never>?
    /// After a failed read, wait for the panel to leave the frame before capturing again,
    /// so a label that can't be read doesn't use up Private Cloud Compute requests in a loop.
    private var autoCaptureSuppressed = false

    init(scanner: any LabelScanning = MockLabelScanner()) {
        self.scanner = scanner
        cameraTarget = SampleLabels.all[0]
        liveScanner = LiveScanner.isSupported ? LiveScanner() : nil
        liveScanner?.onPanelChange = { [weak self] found in self?.panelChanged(found: found) }
    }

    var availableDetents: Set<PresentationDetent> { phase == .result ? [.medium, .large] : [.scanning] }

    /// Shows the live camera and captures automatically once the panel is steady.
    func startScanning() {
        autoCapture?.cancel()
        labelFound = false
        phase = .scanning
        detent = .scanning
        if let liveScanner {
            frozenFrame = nil
            autoCaptureSuppressed = false
            Task {
                if liveScanner.access == .unknown { await liveScanner.requestAccess() }
                liveScanner.isActive = liveScanner.access == .granted
            }
            return
        }
        cameraTarget = SampleLabels.all[nextSample % SampleLabels.all.count]
        nextSample += 1
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
        if liveScanner != nil { return await captureLive() }
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

    // MARK: Live camera

    /// Starts the hold-still countdown when a panel comes into view, and cancels it when it leaves.
    private func panelChanged(found: Bool) {
        guard phase == .scanning, frozenFrame == nil else { return }
        autoCapture?.cancel()
        withAnimation { labelFound = found }
        guard found else {
            autoCaptureSuppressed = false
            return
        }
        guard !autoCaptureSuppressed else { return }
        autoCapture = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.captureLive()
        }
    }

    /// Takes a full-resolution photo, freezes it behind the sheet and reads it.
    private func captureLive() async {
        guard let liveScanner, phase == .scanning, !isReading, frozenFrame == nil else { return }
        let image: UIImage
        do { image = try await liveScanner.capturePhoto() } catch {
            readError = error.localizedDescription
            return
        }
        frozenFrame = image
        liveScanner.isActive = false
        labelFound = false
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        switch await read(imageData: data) {
        case .success(let scan):
            current = scan
            withAnimation(.snappy) {
                phase = .result
                detent = .medium
            }
        case .failure:
            // Show the error and go back to the live camera; don't retry until the panel is moved away.
            autoCaptureSuppressed = true
            frozenFrame = nil
            liveScanner.isActive = true
        }
    }

    /// Reads a screenshot or photo with the backend chosen in Settings and adds it to history.
    func read(imageData: Data, backend: Backend = Backend.selected) async -> Result<Scan, any Error> {
        isReading = true
        readError = nil
        defer { isReading = false }
        do {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = Self.uprightImage(from: source) else { throw ImageError.unreadable }
            let label = try await LabelReaders.make(backend).read(image)
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
        liveScanner?.isActive = false
        guard case .success(let scan) = await read(imageData: imageData) else {
            liveScanner?.isActive = liveScanner?.access == .granted
            return
        }
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

    /// The image with its EXIF orientation applied. Camera photos are stored sideways with a rotation tag,
    /// and OCR and the models read the pixels as they are.
    private static func uprightImage(from source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 3000,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func photo(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 1600,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return AIAndReader.jpeg(image, quality: 0.8)
    }
}

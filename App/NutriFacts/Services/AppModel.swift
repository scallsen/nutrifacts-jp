import CoreGraphics
import ImageIO
import SwiftUI
import Vision

struct Scan: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    var panel: LabelPanel
    /// What read the label. Nil for the simulated camera.
    var backend: Backend? = nil
}

extension PresentationDetent {
    static var scanning: PresentationDetent { .height(250) }
}

@MainActor @Observable
final class AppModel {
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
    /// A real scan in progress (a screenshot or photo).
    private(set) var isReading = false
    /// Goes up each time a photo is taken, for the shutter flash and haptic.
    private(set) var captureCount = 0
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
        guard phase == .scanning else { return }
        captureCount += 1
        guard let panel = try? await scanner.scan(cameraTarget) else { return }
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

    /// The latest version of a scan, e.g. after its basis size was confirmed.
    func latest(_ scan: Scan) -> Scan { history.first { $0.id == scan.id } ?? scan }

    /// Sets the size of a basis printed without one (1個当たり) once the user confirms it.
    func confirmBasis(of scan: Scan, amount: Double, unit: PackUnit) {
        var updated = latest(scan)
        updated.panel.confirmBasis(amount: amount, unit: unit)
        if let i = history.firstIndex(where: { $0.id == scan.id }) { history[i] = updated }
        if current?.id == scan.id { current = updated }
    }

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
            // Hand over before capturing: captureLive cancels any pending auto-capture,
            // and the read runs inside this task.
            self?.autoCapture = nil
            await self?.captureLive()
        }
    }

    /// Takes a full-resolution photo, freezes it behind the sheet and reads it.
    private func captureLive() async {
        guard let liveScanner, phase == .scanning, !isReading, frozenFrame == nil else { return }
        captureCount += 1
        let data: Data
        do { data = try await liveScanner.capturePhoto() } catch CameraEngine.CaptureError.busy {
            return // the shutter and auto-capture fired together; the first one wins
        } catch {
            readError = error.localizedDescription
            return
        }
        autoCapture?.cancel()
        frozenFrame = UIImage(data: data)
        liveScanner.isActive = false
        labelFound = false
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
            // Find the panel while the model reads, so the saved photo is just the label.
            async let crop = Self.panelCrop(of: image)
            let label = try await LabelReaders.make(backend).read(image)
            let photo = await crop.flatMap { AIAndReader.jpeg($0, quality: 0.8) } ?? Self.photo(from: source)
            let scan = Scan(date: .now, panel: try label.toPanel(photo: photo), backend: backend)
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

    /// The nutrition panel cut out of a photo: lines with panel words, plus the text level with them
    /// (the values), with a margin. Nil when no panel words are found, so the whole photo is kept.
    private nonisolated static func panelCrop(of image: CGImage) async -> CGImage? {
        var request = RecognizeTextRequest()
        request.recognitionLanguages = [Locale.Language(identifier: "ja-JP"), Locale.Language(identifier: "en-US")]
        request.recognitionLevel = .accurate // the fast recogniser only reads Latin text
        guard let observations = try? await request.perform(on: image) else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        let boxes = observations.map { ($0.topCandidates(1).first?.string ?? "", $0.boundingBox.toImageCoordinates(size, origin: .upperLeft)) }
        let panelBoxes = boxes.filter { text, _ in CameraEngine.panelWords.contains { text.contains($0) } }.map(\.1)
        guard var panel = panelBoxes.first else { return nil }
        for box in panelBoxes.dropFirst() { panel = panel.union(box) }
        for (_, box) in boxes where box.midY >= panel.minY && box.midY <= panel.maxY { panel = panel.union(box) }
        let margin = max(panel.width, panel.height) * 0.06
        let rect = panel.insetBy(dx: -margin, dy: -margin).intersection(CGRect(origin: .zero, size: size)).integral
        return image.cropping(to: rect)
    }

    private static func photo(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 1600,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return AIAndReader.jpeg(image, quality: 0.8)
    }
}

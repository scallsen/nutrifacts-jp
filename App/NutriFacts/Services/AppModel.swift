import CoreGraphics
import ImageIO
import SwiftUI
import Vision

struct Scan: Identifiable, Hashable, Codable {
    var id = UUID()
    let date: Date
    var panel: LabelPanel
    /// Which model read the label. Nil for the simulated camera.
    var readBy: ReadBy? = nil
    /// Where the time went. Nil for the simulated camera.
    var timing: ScanTiming? = nil
    /// The ingredients box (一括表示), from an optional second scan.
    var box: ExtractedIngredientsBox? = nil
    /// The photo the box was read from.
    var boxPhoto: Data? = nil
    /// What the model returned for the panel, before the app mapped it. Nil for the simulated camera.
    var reading: ExtractedLabel? = nil
    /// The whole photo the model read, uncropped. Debug builds only, for Settings › Debug › Export Scans.
    var framePhoto: Data? = nil
}

extension Scan {
    /// What History and the result call this scan: the product name in English, else as printed, else the
    /// food type from the ingredients box (名称). Nil when none of them were in the photos.
    var title: String? {
        let candidates = [panel.productName?.english, panel.productName?.japanese, box?.category.english,
                          box?.category.japanese, panel.nickname]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    /// The name as printed, when the title is its translation.
    var printedTitle: String? {
        guard let name = panel.productName, !name.english.isEmpty, !name.japanese.isEmpty, name.english != name.japanese else { return nil }
        return name.japanese
    }
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
    /// Every scan, newest first. Saved on this iPhone by `store`.
    private(set) var history: [Scan] = []
    /// A real scan in progress (a screenshot or photo).
    private(set) var isReading = false
    /// Goes up each time a photo is taken, for the shutter flash and haptic.
    private(set) var captureCount = 0
    /// Why the last real scan failed, shown on the scanning sheet.
    var readError: String?
    /// Set while the camera is looking for the ingredients box of this scan, instead of a new label.
    private(set) var ingredientsFor: Scan.ID?
    /// A photo of the ingredients box taken while looking for the nutrition panel. It's read alongside
    /// the panel, so the box doesn't need a second scan. `reading` starts with the panel's read.
    private(set) var savedBox: (photo: Data, reading: Task<(box: ExtractedIngredientsBox, photo: Data)?, Never>?)?
    /// The scan whose saved box is being read, for the result's "Reading the ingredients…" row.
    private(set) var readingBoxFor: Scan.ID?
    /// Set when an ingredients scan finishes, so the result scrolls to the box. The result clears it.
    var scrollToIngredients: Scan.ID?

    /// The real camera. Nil in the Simulator, which uses the simulated camera instead.
    let liveScanner: LiveScanner?
    /// The captured photo, shown behind the sheet while it's read and on the result.
    private(set) var frozenFrame: UIImage?

    private let scanner: any LabelScanning
    private let store: ScanStore
    private var nextSample = 0
    private var autoCapture: Task<Void, Never>?
    /// After a failed read, wait for the panel to leave the frame before capturing again,
    /// so a label that can't be read doesn't use up Private Cloud Compute requests in a loop.
    private var autoCaptureSuppressed = false

    init(scanner: any LabelScanning = MockLabelScanner(), store: ScanStore = .shared) {
        self.scanner = scanner
        self.store = store
        history = store.load()
        cameraTarget = SampleLabels.all[0]
        liveScanner = LiveScanner.isSupported ? LiveScanner() : nil
        liveScanner?.onSightChange = { [weak self] sight in self?.sightChanged(sight) }
    }

    var availableDetents: Set<PresentationDetent> { phase == .result ? [.medium, .large] : [.scanning] }

    /// Shows the live camera and captures automatically once the panel is steady.
    func startScanning() {
        autoCapture?.cancel()
        ingredientsFor = nil
        savedBox = nil
        liveScanner?.lookingFor = .panel
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

    /// Opens the camera for the ingredients box of a scan. The result comes back with the box added.
    func scanIngredients(for scan: Scan) {
        autoCapture?.cancel()
        readError = nil
        ingredientsFor = scan.id
        labelFound = false
        frozenFrame = nil
        autoCaptureSuppressed = false
        liveScanner?.lookingFor = .ingredientsBox
        liveScanner?.isActive = liveScanner?.access == .granted
        withAnimation(.snappy) {
            phase = .scanning
            detent = .scanning
        }
    }

    /// Leaves the ingredients scan and goes back to the result without a box.
    func cancelIngredientsScan() {
        autoCapture?.cancel()
        ingredientsFor = nil
        readError = nil
        labelFound = false
        liveScanner?.isActive = false
        liveScanner?.lookingFor = .panel
        withAnimation(.snappy) {
            phase = .result
            detent = .medium
        }
    }

    func capture(fromAutoCapture: Bool = false) async {
        if !fromAutoCapture { autoCapture?.cancel() }
        if liveScanner != nil { return await captureLive() }
        guard ingredientsFor == nil else {
            readError = "Scanning the ingredients box needs the camera."
            return
        }
        guard phase == .scanning else { return }
        captureCount += 1
        guard let panel = try? await scanner.scan(cameraTarget) else { return }
        let scan = Scan(date: .now, panel: panel)
        insert(scan)
        current = scan
        withAnimation(.snappy) {
            labelFound = false
            phase = .result
            detent = .medium
        }
    }

    func clearHistory() {
        history.removeAll()
        store.deleteAll()
    }

    func delete(_ ids: some Sequence<Scan.ID>) {
        let ids = Set(ids)
        history.removeAll { ids.contains($0.id) }
        ids.forEach(store.delete)
    }

    /// Adds a new scan to the top of History and saves it.
    private func insert(_ scan: Scan) {
        history.insert(scan, at: 0)
        store.save(scan)
    }

    /// Replaces a scan everywhere it's shown, and saves it.
    private func update(_ scan: Scan) {
        guard let i = history.firstIndex(where: { $0.id == scan.id }) else { return }
        history[i] = scan
        if current?.id == scan.id { current = scan }
        store.save(scan)
    }

    /// The latest version of a scan, e.g. after its basis size was confirmed.
    func latest(_ scan: Scan) -> Scan { history.first { $0.id == scan.id } ?? scan }

    /// Sets the size of a basis printed without one (1個当たり) once the user confirms it.
    func confirmBasis(of scan: Scan, amount: Double, unit: PackUnit) {
        var updated = latest(scan)
        updated.panel.confirmBasis(amount: amount, unit: unit)
        update(updated)
    }

    /// Sets the whole-pack size the user typed, so the result can show the whole pack.
    func setPackSize(of scan: Scan, amount: Double) {
        var updated = latest(scan)
        updated.panel.setPack(amount: amount)
        update(updated)
    }

    // MARK: Live camera

    /// Starts the hold-still countdown when a panel comes into view, and cancels it when it leaves.
    /// While looking for the panel, an ingredients box in view is captured too, once, and saved for later.
    private func sightChanged(_ sight: LiveScanner.Sight) {
        guard phase == .scanning, frozenFrame == nil else { return }
        autoCapture?.cancel()
        let found = sight == .label || (sight == .otherLabel && canSaveBox && savedBox == nil)
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

    /// Only the nutrition scan saves a box for later; the ingredients scan reads it straight away.
    private var canSaveBox: Bool { ingredientsFor == nil }

    /// Takes a full-resolution photo, freezes it behind the sheet and reads it.
    private func captureLive() async {
        guard let liveScanner, phase == .scanning, !isReading, frozenFrame == nil else { return }
        captureCount += 1
        let clock = ContinuousClock()
        let captureStarted = clock.now
        let data: Data
        do { data = try await liveScanner.capturePhoto() } catch CameraEngine.CaptureError.busy {
            return // the shutter and auto-capture fired together; the first one wins
        } catch {
            readError = error.localizedDescription
            return
        }
        autoCapture?.cancel()
        // Only the ingredients box in view, while looking for the panel: keep it and look on.
        if canSaveBox, liveScanner.sight == .otherLabel {
            savedBox = (data, nil)
            readError = nil
            autoCaptureSuppressed = true
            withAnimation { labelFound = false }
            return
        }
        frozenFrame = UIImage(data: data)
        liveScanner.isActive = false
        labelFound = false
        if let id = ingredientsFor {
            if await readIngredients(imageData: data, for: id) {
                frozenFrame = nil
            } else {
                autoCaptureSuppressed = true
                frozenFrame = nil
                liveScanner.isActive = true
            }
            return
        }
        let boxReading = startBoxRead(alongside: data)
        switch await read(imageData: data, capture: clock.now - captureStarted) {
        case .success(let scan):
            current = scan
            attachBox(boxReading, to: scan.id)
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

    /// Longest side of the image the model reads. The whole frame is sent, uncropped, so nothing on the
    /// pack is missed; this only caps the resolution. Lower is faster (fewer image tokens, smaller upload),
    /// but small print needs enough pixels. Check ScanTiming before changing it.
    nonisolated static let readMaxSide = 1600

    /// Reads a screenshot or photo with the backend chosen in Settings and adds it to history.
    /// `capture` is how long the live camera took to take the photo, for ScanTiming.
    func read(imageData: Data, backend: Backend = Backend.selected, capture: Duration? = nil) async -> Result<Scan, any Error> {
        isReading = true
        readError = nil
        defer { isReading = false }
        let clock = ContinuousClock()
        let started = clock.now
        do {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = Self.uprightImage(from: source) else { throw ImageError.unreadable }
            let prepared = clock.now
            // Find the panel while the model reads, so the saved photo is just the label.
            async let crop = Self.labelCrop(of: image)
            let reading = try await LabelReaders.make(backend).read(image)
            let readDone = clock.now
            let photo = await crop.flatMap { AIAndReader.jpeg($0, quality: 0.8) } ?? Self.photo(from: source)
            let finished = clock.now
            let timing = ScanTiming(capture: capture, prepare: prepared - started, read: readDone - prepared,
                                    cropWait: finished - readDone, total: (finished - started) + (capture ?? .zero),
                                    imageSize: "\(image.width)×\(image.height)", details: reading.details)
            ScanTiming.logger.info("\(timing.summary, privacy: .public)")
            var scan = Scan(date: .now, panel: try reading.label.toPanel(photo: photo), readBy: reading.readBy, timing: timing,
                            reading: reading.label)
            #if DEBUG
            scan.framePhoto = AIAndReader.jpeg(image, quality: 0.8)
            #endif
            insert(scan)
            return .success(scan)
        } catch {
            ScanTiming.logger.error("read failed with \(backend.title, privacy: .public) after \(ScanTiming.seconds(clock.now - started), privacy: .public): \(error.localizedDescription, privacy: .public)")
            readError = error.localizedDescription
            return .failure(error)
        }
    }

    /// Reads the ingredients box and adds it to the scan, then goes back to its result.
    /// Returns false when it couldn't be read; the error is in `readError`.
    private func readIngredients(imageData: Data, for id: Scan.ID) async -> Bool {
        isReading = true
        readError = nil
        defer { isReading = false }
        do {
            let (box, photo) = try await Self.readBox(imageData: imageData)
            add(box, photo: photo, to: id)
            ingredientsFor = nil
            liveScanner?.lookingFor = .panel
            scrollToIngredients = id
            withAnimation(.snappy) {
                phase = .result
                detent = .medium
            }
            return true
        } catch {
            ScanTiming.logger.error("ingredients read failed: \(error.localizedDescription, privacy: .public)")
            readError = error.localizedDescription
            return false
        }
    }

    /// Reads a photo of the ingredients box, and makes the smaller copy the scan keeps.
    private static func readBox(imageData: Data) async throws -> (box: ExtractedIngredientsBox, photo: Data) {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = uprightImage(from: source) else { throw ImageError.unreadable }
        // Find the box while the model reads, so the saved photo is just the box, like the panel's.
        async let crop = labelCrop(of: image, words: CameraEngine.boxWords)
        let (box, _) = try await ExtractedIngredientsBox.read(image)
        return (box, await crop.flatMap { AIAndReader.jpeg($0, quality: 0.8) } ?? photo(from: source) ?? imageData)
    }

    /// Adds a box to a scan, and fills its pack size and piece count from 内容量.
    private func add(_ box: ExtractedIngredientsBox, photo: Data, to id: Scan.ID) {
        guard var scan = history.first(where: { $0.id == id }) ?? (current?.id == id ? current : nil) else { return }
        scan.box = box
        scan.boxPhoto = photo
        // The count first: a suggested size divides by it.
        scan.panel.apply(contentsCount: box.netContentsCount, printed: box.netContentsText)
        if let contents = box.netContents {
            scan.panel.apply(netContents: contents.amount, unit: contents.unit, count: box.netContentsCount,
                             printed: box.netContentsText)
        }
        update(scan)
    }

    /// A read of the ingredients box that runs alongside the panel's. `seen` finishes first, once it's known
    /// whether there's a box to read at all, so the result only says "Reading the ingredients…" when there is.
    private struct BoxReading {
        var seen: Task<Bool, Never>
        var result: Task<(box: ExtractedIngredientsBox, photo: Data)?, Never>
    }

    /// Starts reading the ingredients box alongside the panel's read: the box photo saved while looking for
    /// the panel, or else the panel's own photo when the box is in it too, so one photo gives both.
    private func startBoxRead(alongside panelPhoto: Data) -> BoxReading? {
        if let saved = startSavedBoxRead() { return BoxReading(seen: Task { true }, result: saved) }
        let seen = Task { await Self.showsIngredientsBox(panelPhoto) }
        let result = Task { () -> (box: ExtractedIngredientsBox, photo: Data)? in
            guard await seen.value else { return nil }
            do { return try await Self.readBox(imageData: panelPhoto) } catch {
                ScanTiming.logger.error("ingredients read from the panel's photo failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return BoxReading(seen: seen, result: result)
    }

    /// Starts reading the saved ingredients box, if there is one.
    /// A read that already ran (the panel failed last time) is reused.
    private func startSavedBoxRead() -> Task<(box: ExtractedIngredientsBox, photo: Data)?, Never>? {
        guard let saved = savedBox else { return nil }
        if let reading = saved.reading { return reading }
        let reading = Task { () -> (box: ExtractedIngredientsBox, photo: Data)? in
            do { return try await Self.readBox(imageData: saved.photo) } catch {
                ScanTiming.logger.error("saved ingredients read failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        savedBox = (saved.photo, reading)
        return reading
    }

    /// Adds the box to the panel's scan once its read finishes. The result shows it reading meanwhile.
    private func attachBox(_ reading: BoxReading?, to id: Scan.ID) {
        guard let reading else { return }
        savedBox = nil
        Task {
            guard await reading.seen.value else { return }
            readingBoxFor = id
            if let (box, photo) = await reading.result.value { add(box, photo: photo, to: id) }
            if readingBoxFor == id { readingBoxFor = nil }
        }
    }

    /// Whether a photo shows the ingredients box (一括表示): its 原材料名 heading, or three of its headings,
    /// the same test the live camera uses. On device, with Vision.
    nonisolated static func showsIngredientsBox(_ imageData: Data) async -> Bool {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil), let image = uprightImage(from: source) else { return false }
        var request = RecognizeTextRequest()
        request.recognitionLanguages = [Locale.Language(identifier: "ja-JP")]
        request.recognitionLevel = .accurate // the fast recogniser only reads Latin text
        guard let observations = try? await request.perform(on: image) else { return false }
        return CameraEngine.isIngredientsBox(observations.compactMap { $0.topCandidates(1).first?.string })
    }

    /// Reads an image from the app and shows the result sheet.
    func readAndShow(imageData: Data) async {
        autoCapture?.cancel()
        liveScanner?.isActive = false
        if let id = ingredientsFor {
            if await !readIngredients(imageData: imageData, for: id) {
                liveScanner?.isActive = liveScanner?.access == .granted
            }
            return
        }
        let boxReading = startBoxRead(alongside: imageData)
        guard case .success(let scan) = await read(imageData: imageData) else {
            liveScanner?.isActive = liveScanner?.access == .granted
            return
        }
        current = scan
        attachBox(boxReading, to: scan.id)
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
    private nonisolated static func uprightImage(from source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: readMaxSide,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The label cut out of a photo: lines with the label's words (the nutrition panel's, or the ingredients
    /// box's headings), plus the text level with them (the values), with a margin. Nil when none of the
    /// words are found, so the whole photo is kept.
    private nonisolated static func labelCrop(of image: CGImage, words: [String] = CameraEngine.panelWords) async -> CGImage? {
        var request = RecognizeTextRequest()
        request.recognitionLanguages = [Locale.Language(identifier: "ja-JP"), Locale.Language(identifier: "en-US")]
        request.recognitionLevel = .accurate // the fast recogniser only reads Latin text
        guard let observations = try? await request.perform(on: image) else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        let boxes = observations.map { ($0.topCandidates(1).first?.string ?? "", $0.boundingBox.toImageCoordinates(size, origin: .upperLeft)) }
        let panelBoxes = boxes.filter { text, _ in words.contains { text.contains($0) } }.map(\.1)
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

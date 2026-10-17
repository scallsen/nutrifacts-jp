@preconcurrency import AVFoundation
import UIKit
import Vision

/// The capture session behind the live camera: a preview, a frame every ~0.5 s for panel
/// detection, and full-resolution photos. Everything runs on device.
/// Session work happens on `sessionQueue`, frame analysis on `videoQueue`.
nonisolated final class CameraEngine: NSObject, @unchecked Sendable {
    /// Where the panel's lines are in a portrait frame, normalised with the origin at the top left.
    /// Nil when no panel is in view. `wrongRect` is the other kind of label (the ingredients box while
    /// looking for the panel, or the other way round), when only that one is in view.
    typealias Detection = (rect: CGRect?, wrongRect: CGRect?, imageSize: CGSize)

    let session = AVCaptureSession()
    /// Called on the main actor after each analysed frame.
    var onDetection: (@MainActor (Detection) -> Void)?

    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoQueue = DispatchQueue(label: "camera.video")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false
    private var lastAnalysis = Date.distantPast
    /// What to look for. Set from the main actor and read on `videoQueue`; a stale read only affects one frame.
    var lookingFor: LookingFor = .panel

    enum LookingFor: Sendable { case panel, ingredientsBox }
    private var photoContinuation: CheckedContinuation<Data, any Error>?

    /// Portrait: the back camera's sensor is landscape, so frames are rotated 90°.
    private static let portraitAngle: CGFloat = 90

    static var hasCamera: Bool { AVCaptureDevice.default(for: .video) != nil }

    func start() {
        sessionQueue.async { [self] in
            if !isConfigured { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        // A virtual multi-camera device switches lenses for close-up (macro) focus on Pro models.
        let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)

        if (try? device.lockForConfiguration()) != nil {
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            device.unlockForConfiguration()
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        for output in [photoOutput, videoOutput] as [AVCaptureOutput] {
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(Self.portraitAngle) {
                connection.videoRotationAngle = Self.portraitAngle
            }
        }
        isConfigured = true
    }

    // MARK: Photo

    enum CaptureError: LocalizedError {
        case busy, notRunning, noData
        var errorDescription: String? {
            switch self {
            case .busy: "Already taking a photo."
            case .notRunning: "The camera isn't running."
            case .noData: "The camera didn't return a photo. Try again."
            }
        }
    }

    /// A full-resolution photo (HEIC/JPEG data with its orientation tag).
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard photoContinuation == nil else { return continuation.resume(throwing: CaptureError.busy) }
                guard session.isRunning else { return continuation.resume(throwing: CaptureError.notRunning) }
                photoContinuation = continuation
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        sessionQueue.async { [self] in
            let continuation = photoContinuation
            photoContinuation = nil
            if let error { continuation?.resume(throwing: error) }
            else if let data = photo.fileDataRepresentation() { continuation?.resume(returning: data) }
            else { continuation?.resume(throwing: CaptureError.noData) }
        }
    }
}

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Lines that only appear on a nutrition panel, with the spec's alternate spellings.
    static let panelWords = ["栄養成分表示", "栄養成分", "熱量", "エネルギー", "たんぱく質", "蛋白質", "タンパク質",
                             "脂質", "炭水化物", "食塩相当量", "糖質", "糖類", "食物繊維"]

    /// Headings of the ingredients box (一括表示).
    static let boxWords = ["原材料名", "名称", "品名", "内容量", "賞味期限", "消費期限", "保存方法", "製造者", "販売者", "輸入者"]

    private static let panelLabel = (words: panelWords, heading: "栄養成分表示")
    private static let boxLabel = (words: boxWords, heading: "原材料名")

    /// The words of one kind of label seen in a frame, and where they are.
    private struct Match {
        var hits = Set<String>()
        var rect: CGRect?

        mutating func add(_ words: [String], _ box: CGRect) {
            guard !words.isEmpty else { return }
            hits.formUnion(words)
            rect = rect.map { $0.union(box) } ?? box
        }

        /// The heading alone (栄養成分表示 or 原材料名), or three of the label's words.
        func isLabel(heading: String) -> Bool { hits.contains(heading) || hits.count >= 3 }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Japanese needs the accurate recogniser, so analyse about two frames a second, not every frame.
        guard Date.now.timeIntervalSince(lastAnalysis) > 0.5, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = .now

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request])

        let (wanted, other) = lookingFor == .panel ? (Self.panelLabel, Self.boxLabel) : (Self.boxLabel, Self.panelLabel)
        var found = (wanted: Match(), other: Match())
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            // Vision's origin is bottom left; flip to top left.
            let b = observation.boundingBox
            let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            found.wanted.add(wanted.words.filter { text.contains($0) }, box)
            found.other.add(other.words.filter { text.contains($0) }, box)
        }
        let isWanted = found.wanted.isLabel(heading: wanted.heading)
        let isOther = !isWanted && found.other.isLabel(heading: other.heading)
        let size = CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
        let detection: Detection = (isWanted ? found.wanted.rect : nil, isOther ? found.other.rect : nil, size)
        Task { @MainActor [onDetection] in onDetection?(detection) }
    }
}

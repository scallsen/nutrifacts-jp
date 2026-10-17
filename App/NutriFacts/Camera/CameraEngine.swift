@preconcurrency import AVFoundation
import UIKit
import Vision

/// The capture session behind the live camera: a preview, a frame every ~0.5 s for panel
/// detection, and full-resolution photos. Everything runs on device.
/// Session work happens on `sessionQueue`, frame analysis on `videoQueue`.
nonisolated final class CameraEngine: NSObject, @unchecked Sendable {
    /// Where the panel's lines are in a portrait frame, normalised with the origin at the top left.
    /// Nil when no panel is in view.
    typealias Detection = (rect: CGRect?, imageSize: CGSize)

    let session = AVCaptureSession()
    /// Called on the main actor after each analysed frame.
    var onDetection: (@MainActor (Detection) -> Void)?

    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoQueue = DispatchQueue(label: "camera.video")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false
    private var lastAnalysis = Date.distantPast
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

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Japanese needs the accurate recogniser, so analyse about two frames a second, not every frame.
        guard Date.now.timeIntervalSince(lastAnalysis) > 0.5, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = .now

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request])

        var rect: CGRect?
        var hits = Set<String>()
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            let found = Self.panelWords.filter { text.contains($0) }
            guard !found.isEmpty else { continue }
            hits.formUnion(found)
            // Vision's origin is bottom left; flip to top left.
            let b = observation.boundingBox
            let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            rect = rect.map { $0.union(box) } ?? box
        }
        // The heading alone, or three nutrient lines, counts as a panel.
        let isPanel = hits.contains("栄養成分表示") || hits.count >= 3
        let size = CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
        let detection: Detection = (isPanel ? rect : nil, size)
        Task { @MainActor [onDetection] in onDetection?(detection) }
    }
}

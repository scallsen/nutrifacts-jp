@preconcurrency import AVFoundation
import SwiftUI

/// The real camera, watching for a 栄養成分表示 panel. Everything it sees stays on the device;
/// only the captured photo is sent to the backend chosen in Settings.
/// Not available in the Simulator, where the app falls back to `CameraBackdrop`.
@MainActor @Observable
final class LiveScanner {
    enum Access { case unknown, granted, denied }

    /// False in the Simulator, which has no camera.
    static var isSupported: Bool { CameraEngine.hasCamera }

    private(set) var access: Access = .unknown
    /// Where the panel is on screen, in the preview's coordinates. Nil while no panel is in view.
    private(set) var panelRect: CGRect?
    /// Called when a panel comes into or goes out of view.
    var onPanelChange: ((Bool) -> Void)?
    /// Size of the preview on screen, for placing the brackets.
    var viewSize: CGSize = .zero

    /// Whether the camera should be running.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive { engine.start() } else { engine.stop(); clearPanel() }
        }
    }

    @ObservationIgnored let engine = CameraEngine()
    @ObservationIgnored private var isCapturing = false

    init() {
        engine.onDetection = { [weak self] detection in self?.update(detection) }
    }

    func requestAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: access = .granted
        case .notDetermined: access = await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        default: access = .denied
        }
    }

    /// A full-resolution photo of what the camera sees now. Only one capture runs at a time.
    func capturePhoto() async throws -> Data {
        guard !isCapturing else { throw CameraEngine.CaptureError.busy }
        isCapturing = true
        defer { isCapturing = false }
        return try await engine.capturePhoto()
    }

    private func update(_ detection: CameraEngine.Detection) {
        guard isActive else { return }
        let newRect = detection.rect.map { toView($0, imageSize: detection.imageSize) }
        let changed = (newRect == nil) != (panelRect == nil)
        withAnimation(.snappy) { panelRect = newRect }
        if changed { onPanelChange?(newRect != nil) }
    }

    func clearPanel() {
        let had = panelRect != nil
        panelRect = nil
        if had { onPanelChange?(false) }
    }

    /// Maps a normalised rect in the frame to the preview, which fills the screen (aspect fill).
    private func toView(_ r: CGRect, imageSize: CGSize) -> CGRect {
        guard viewSize != .zero, imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let shown = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let dx = (shown.width - viewSize.width) / 2, dy = (shown.height - viewSize.height) / 2
        return CGRect(x: r.minX * shown.width - dx, y: r.minY * shown.height - dy,
                      width: r.width * shown.width, height: r.height * shown.height)
    }
}

/// The camera preview layer.
struct LiveCameraView: UIViewRepresentable {
    let scanner: LiveScanner

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = scanner.engine.session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90),
           connection.videoRotationAngle != 90 {
            connection.videoRotationAngle = 90
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
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
                GeometryReader { geo in
                    LiveCameraView(scanner: scanner)
                        .onAppear { scanner.viewSize = geo.size }
                        .onChange(of: geo.size) { _, size in scanner.viewSize = size }
                }
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

import SwiftUI

struct Scan: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let panel: LabelPanel
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
}

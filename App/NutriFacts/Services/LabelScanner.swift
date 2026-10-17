import Foundation

/// Turns a camera frame into a parsed panel.
/// The real version will use VisionKit's DataScannerViewController and Vision's RecognizeDocumentsRequest.
protocol LabelScanning: Sendable {
    func scan(_ target: LabelPanel) async throws -> LabelPanel
}

/// Placeholder: "reads" whichever sample label the simulated camera is pointing at.
struct MockLabelScanner: LabelScanning {
    func scan(_ target: LabelPanel) async throws -> LabelPanel {
        try await Task.sleep(for: .milliseconds(350))
        return target
    }
}

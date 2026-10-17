import Foundation

/// Turns a camera frame into a parsed panel.
/// Used by the simulated camera only. Real scans go through `AppModel.read(imageData:)`.
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

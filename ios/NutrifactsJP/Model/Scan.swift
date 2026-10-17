import Foundation
import SwiftData

/// One scored screenshot. Only the transcription is stored; the score is recomputed from it,
/// so rubric or daily-value updates apply to old scans too.
@Model
final class Scan {
    var date: Date
    var backendRaw: String
    var thumbnail: Data?
    var labelData: Data?
    var errorMessage: String?
    /// Weight the user entered for a basis printed without one (e.g. 1袋当たり).
    var userBasisAmount: Double?

    init(date: Date = .now, backend: Backend, thumbnail: Data?, label: ExtractedLabel?, errorMessage: String? = nil) {
        self.date = date
        self.backendRaw = backend.rawValue
        self.thumbnail = thumbnail
        self.labelData = label.flatMap { try? JSONEncoder().encode($0) }
        self.errorMessage = errorMessage
    }

    var backend: Backend { Backend(rawValue: backendRaw) ?? .onDevice }

    var label: ExtractedLabel? { labelData.flatMap { try? JSONDecoder().decode(ExtractedLabel.self, from: $0) } }

    var panel: NutritionPanel? {
        guard var panel = try? label?.toPanel() else { return nil }
        if panel.basis.amount == nil, let userBasisAmount { panel.basis.amount = userBasisAmount }
        return panel
    }

    var outcome: ScanOutcome { ScanOutcome(scan: self) }
}

/// Everything a result screen needs, derived from a scan.
nonisolated enum ScanOutcome {
    case failed(String)
    case noPanel
    case needsBasisAmount(NutritionPanel)
    case scored(NutritionPanel, HealthScore, [SanityIssue])

    init(scan: Scan) {
        if let message = scan.errorMessage { self = .failed(message); return }
        guard let panel = scan.panel else { self = .noPanel; return }
        self.init(panel: panel)
    }

    init(panel: NutritionPanel) {
        switch HealthScorer.score(panel) {
        case .success(let score): self = .scored(panel, score, SanityChecks.run(panel))
        case .failure: self = .needsBasisAmount(panel)
        }
    }

    /// One line for Shortcuts / Siri.
    var summary: String {
        switch self {
        case .failed(let message): message
        case .noPanel: "No nutrition panel found in the screenshot."
        case .needsBasisAmount(let panel): "Read the label, but “\(panel.basis.label)” has no weight. Open Nutrifacts to add it."
        case .scored(let panel, let score, _):
            "\(panel.productName.map { "\($0): " } ?? "")Grade \(score.gradeText) · \(score.scoreText)/100"
                + (score.undisclosed.isEmpty ? "" : ". Not disclosed: \(score.undisclosed.map(\.english).joined(separator: ", ")).")
        }
    }
}

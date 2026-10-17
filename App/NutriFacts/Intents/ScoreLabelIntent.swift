import AppIntents
import SwiftUI
import UniformTypeIdentifiers

/// The Action Button entry point. Apps can't capture the screen themselves, so a Shortcut runs
/// "Take Screenshot" and passes the image here. With the Camera app open, that's the viewfinder.
struct ScoreLabelIntent: AppIntent {
    static let title: LocalizedStringResource = "Score Nutrition Label"
    static let description = IntentDescription("Reads the Japanese nutrition panel in a screenshot or photo and grades it.")
    static let openAppWhenRun = false

    @Parameter(title: "Screenshot", supportedContentTypes: [.image], inputConnectionBehavior: .connectToPreviousIntentResult)
    var image: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Score nutrition label in \(\.$image)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let result = await AppModel.shared.read(imageData: image.data)
        let summary: String
        switch result {
        case .success(let scan):
            let score = PanelAnalysis(panel: scan.panel, basis: .per100, source: .japan).healthScore()
            summary = "Grade \(score.gradeText) · \(score.scoreText)/100"
                + (score.widenedBy.isEmpty ? "" : ". Not listed: \(score.widenedBy.map(\.english).joined(separator: ", ")).")
        case .failure(let error):
            summary = error.localizedDescription
        }
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary),
                       view: ScoreSnippetView(panel: try? result.get().panel, message: summary))
    }
}

struct NutriFactsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScoreLabelIntent(),
                    phrases: ["Score a nutrition label with \(.applicationName)",
                              "Grade this label with \(.applicationName)"],
                    shortTitle: "Score Label",
                    systemImageName: "text.viewfinder")
    }
}

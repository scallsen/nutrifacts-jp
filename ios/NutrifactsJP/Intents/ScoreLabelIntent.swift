import AppIntents
import SwiftUI
import UniformTypeIdentifiers

/// The Action Button entry point. Apps can't capture the screen themselves, so a Shortcut runs
/// "Take Screenshot" and passes the image here. Setup steps: ios/README.md.
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
        let scan = await ScanService.scan(imageData: image.data)
        let outcome = scan.outcome
        return .result(value: outcome.summary,
                       dialog: IntentDialog(stringLiteral: outcome.summary),
                       view: ScoreSnippetView(outcome: outcome, backend: scan.backend))
    }
}

struct NutrifactsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScoreLabelIntent(),
                    phrases: ["Score a nutrition label with \(.applicationName)",
                              "Grade this label with \(.applicationName)"],
                    shortTitle: "Score Label",
                    systemImageName: "text.viewfinder")
    }
}

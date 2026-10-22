import Foundation
import Testing
@testable import NutriFacts

@MainActor
@Suite struct ExportTests {
    @Test func customFoodFollowsTheTrackersFormAndKeepsMissingLinesMissing() {
        var panel = SampleLabels.chips
        panel.productName = TranslatedText(japanese: "ポテトチップス うすしお味", english: "Potato Chips Lightly Salted")
        let scan = Scan(date: .now, panel: panel)
        let text = NutritionExport.customFood(scan, analysis: PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan))
        #expect(text.components(separatedBy: "\n") == [
            "Potato Chips Lightly Salted",
            "ポテトチップス うすしお味",
            "Serving size: 60 g bag",
            "Calories: 336 kcal",
            "Total fat: 21.6 g",
            "Saturated fat: not listed",
            "Sodium: 236 mg (salt 0.6 g)",
            "Total carbohydrate: 32.4 g",
            "Dietary fiber: not listed",
            "Sugars: not listed",
            "Protein: 3.1 g",
        ])
    }

    @Test func customFoodScalesToTheChosenAmount() {
        let panel = SampleLabels.granola // 50 g serving, 400 g bag
        let text = NutritionExport.customFood(Scan(date: .now, panel: panel), analysis: PanelAnalysis(panel: panel, basis: .per100, source: .japan))
        #expect(text.contains("Serving size: 100 g"))
        let perServing = Double(panel.printed[.energy]!)!
        #expect(text.contains("Calories: \(Int((perServing * 2).rounded())) kcal"))
    }

    @Test func csvHasOneRowPerScanAndQuotesCommas() {
        var panel = SampleLabels.chips
        panel.productName = TranslatedText(japanese: "チップス", english: "Chips, salted")
        let csv = NutritionExport.csv([Scan(date: .now, panel: panel), Scan(date: .now, panel: SampleLabels.granola)])
        let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(rows.count == 3)
        #expect(rows[0].hasPrefix("Date,Product,Product (as printed),Food type,Basis (as printed)"))
        #expect(rows[1].contains(",\"Chips, salted\",チップス,,1袋（60g）当たり,60,g,60,336,3.1,21.6,,32.4,,,,0.6,236,yes,"))
    }
}

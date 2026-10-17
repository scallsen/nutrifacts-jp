import Foundation
import Testing
@testable import NutriFacts

@MainActor
@Suite struct ScoringTests {
    private func score(_ panel: LabelPanel) -> HealthScore {
        PanelAnalysis(panel: panel, basis: .per100, source: .japan).healthScore()
    }

    @Test func fullLabelGetsExactScore() {
        // Granola per 100 g: fat 15.2, sat 5.8, sugars 22.4, salt 0.4, protein 8.6, fibre 7.8.
        let s = score(SampleLabels.granola)
        #expect(s.isExact)
        #expect(abs(s.score.lowerBound - 50.5) < 0.1)
        #expect(s.gradeText == "C")
    }

    @Test func missingSugarsMakesARangeBoundedByNetCarbs() throws {
        var panel = SampleLabels.granola
        panel.printed[.sugars] = nil
        let s = score(panel)
        #expect(!s.isExact)
        let sugars = try #require(s.components.first { $0.key == .sugars })
        #expect(sugars.status == .notDisclosed)
        #expect(abs(sugars.value.upperBound - 64.2) < 0.01) // 糖質 32.1 g × 2
        #expect(s.widenedBy == [.sugars])
    }

    @Test func totalOnlyLabelLeavesSatFatAndSugarsOpen() {
        let s = score(SampleLabels.chips)
        #expect(Set(s.widenedBy) == [.saturatedFat, .sugars])
        #expect(s.bestGrade != s.worstGrade)
        // Undisclosed fibre earns nothing; it's never treated as a measured 0.
        #expect(s.components.first { $0.key == .fibre }?.points == 0...0)
    }

    @Test func printedZeroNeverCostsPoints() throws {
        let fat = try #require(score(SampleLabels.cola).components.first { $0.key == .fat })
        #expect(fat.status == .printedZero)
        #expect(fat.points == 0...0)
    }

    @Test func drinksUseDrinkThresholds() throws {
        // 7.0 g sugars / 100 ml: (7.0 − 2.5) / (11.25 − 2.5) × 25 ≈ 12.9 points.
        let sugars = try #require(score(SampleLabels.milkTea).components.first { $0.key == .sugars })
        #expect(abs(sugars.points.lowerBound + 12.857) < 0.01)
    }
}

@Suite struct ExtractionMappingTests {
    private func label(_ lines: [ExtractedLine], basis: String = "100g当たり", amount: Double = 100) -> ExtractedLabel {
        ExtractedLabel(panelFound: true, productName: "", basisText: basis, basisAmount: amount, basisUnit: .g,
                       netContentsAmount: 0, lines: lines, isEstimate: false)
    }

    private func line(_ n: ExtractedNutrient, _ v: Double, _ unit: String = "g", max: Double? = nil) -> ExtractedLine {
        ExtractedLine(nutrient: n, printedName: n.rawValue, minValue: v, maxValue: max ?? v, unit: unit)
    }

    @Test func missingLinesStayMissing() throws {
        let panel = try label([line(.energy, 200, "kcal"), line(.carbohydrate, 30)]).toPanel(photo: nil)
        #expect(panel.printed[.fibre] == nil)
        #expect(panel.printed[.sugars] == nil)
        #expect(panel.printed[.carbohydrate] == "30")
    }

    @Test func zerosAndDecimalsKeepTheirPrintedForm() throws {
        let panel = try label([line(.fat, 0), line(.salt, 0.08), line(.protein, 21.6)]).toPanel(photo: nil)
        #expect(panel.printed[.fat] == "0")
        #expect(panel.printed[.salt] == "0.08")
        #expect(panel.printed[.protein] == "21.6")
    }

    @Test func sodiumOnlyBecomesSalt() throws {
        let panel = try label([line(.sodium, 1.2, "g")]).toPanel(photo: nil)
        #expect(abs(panel.number(.salt)! - 3.048) < 0.001)
    }

    @Test func basisWithoutAmountIsNotGuessed() {
        var l = label([line(.fat, 3)], basis: "1袋当たり", amount: 0)
        l.netContentsAmount = 85
        #expect(throws: ExtractedLabel.MappingError.self) { try l.toPanel(photo: nil) }
    }

    @Test func drinksUseMillilitres() throws {
        var l = label([line(.sugars, 7)], basis: "100ml当たり")
        l.basisUnit = .ml
        #expect(try l.toPanel(photo: nil).unit == .millilitres)
    }
}

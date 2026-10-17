import Foundation
import Testing
@testable import NutriFacts

@MainActor
@Suite struct ScoringTests {
    private func score(_ panel: LabelPanel) -> HealthScore {
        PanelAnalysis(panel: panel, basis: .per100, source: .japan).healthScore()!
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
                       netContentsAmount: 0, netContentsUnit: .none, netContentsCount: 0, lines: lines, isEstimate: false)
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

    @Test func countBasisIgnoresAMadeUpSize() throws {
        // 1本当たり prints no weight, so a basisAmount of 1 from the model is a misread.
        let panel = try label([line(.fat, 0)], basis: "1本当たり", amount: 1).toPanel(photo: nil)
        #expect(panel.basisAmount == nil)
        #expect(try label([line(.fat, 0)], basis: "1袋（60g）当たり", amount: 60).toPanel(photo: nil).basisAmount == 60)
    }

    @Test func printedZeroShowsAsLow() throws {
        let panel = try label([line(.fat, 0), line(.carbohydrate, 0)]).toPanel(photo: nil)
        let a = PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan)
        #expect(a.level(.fat) == .zero)
        #expect(a.level(.fat)?.word == "Low")
        #expect(a.value(.fat)?.text == "0 g")
    }

    @Test func sodiumOnlyBecomesSalt() throws {
        let panel = try label([line(.sodium, 1.2, "g")]).toPanel(photo: nil)
        #expect(abs(panel.number(.salt)! - 3.048) < 0.001)
    }

    @Test func basisWithoutAmountIsNotGuessed() throws {
        var l = label([line(.fat, 3)], basis: "1袋当たり", amount: 0)
        l.netContentsAmount = 85
        l.netContentsUnit = .g
        let panel = try l.toPanel(photo: nil)
        #expect(panel.basisAmount == nil)
        // No score until the user confirms a size; 内容量 is only offered.
        #expect(PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan).healthScore() == nil)
        #expect(panel.basisSuggestion == BasisSuggestion(amount: 85, unit: .grams, reason: "内容量 85 g"))
    }

    @Test func multipackSuggestionIsPerPiece() throws {
        var l = label([line(.fat, 3)], basis: "1個当たり", amount: 0)
        l.netContentsAmount = 120
        l.netContentsUnit = .g
        l.netContentsCount = 6
        #expect(try l.toPanel(photo: nil).basisSuggestion?.amount == 20)
    }

    @Test func countOnlyContentsGivesNoSuggestion() throws {
        var l = label([line(.fat, 3)], basis: "1個当たり", amount: 0)
        l.netContentsCount = 2
        #expect(try l.toPanel(photo: nil).basisSuggestion == nil)
    }

    @Test @MainActor func confirmingTheBasisEnablesTheScore() throws {
        var l = label([line(.energy, 140, "kcal"), line(.fat, 0), line(.carbohydrate, 35), line(.salt, 0.1)], basis: "1個当たり", amount: 0)
        l.netContentsAmount = 350
        l.netContentsUnit = .ml
        var panel = try l.toPanel(photo: nil)
        panel.confirmBasis(amount: 350, unit: .millilitres)
        #expect(panel.basisShort == "1個 · 350 ml")
        #expect(PanelAnalysis(panel: panel, basis: .per100, source: .japan).healthScore() != nil)
    }

    @Test func basisTextLosesHeadingAndOuterBrackets() {
        #expect(ExtractedLabel.cleanBasis("栄養成分表示（1個当たり）") == "1個当たり")
        #expect(ExtractedLabel.cleanBasis("1食分（50g）当たり") == "1食分（50g）当たり")
        #expect(ExtractedLabel.cleanBasis("(100ml当たり)") == "100ml当たり")
    }

    @Test func drinksUseMillilitres() throws {
        var l = label([line(.sugars, 7)], basis: "100ml当たり")
        l.basisUnit = .ml
        #expect(try l.toPanel(photo: nil).unit == .millilitres)
    }
}

@Suite struct AIAndConfigTests {
    @Test func newUsersDefaultToAIAnd() {
        #expect(Backend.aiAnd.isSupported)
        #expect(Backend.defaultBackend == .aiAnd)
    }

    @Test func appPointsAtTheDeployedWorker() {
        // From Config/NutriFacts.xcconfig via Info.plist.
        #expect(AIAndConfig.current.apiURL?.absoluteString == "https://nutrifacts-api.justin-garcia.workers.dev")
    }
}

import Testing
@testable import NutrifactsJP

@Suite struct ScoringTests {
    private func sample(_ name: String) -> NutritionPanel {
        SampleLabels.all.first { $0.name == name }!.panel
    }

    private func score(_ panel: NutritionPanel) throws -> HealthScore {
        try HealthScorer.score(panel).get()
    }

    @Test func fullLabelGetsExactScore() throws {
        // Granola per 100 g: fat 15.2, sat 5.8, sugars 22.4, salt 0.4, protein 8.6, fibre 7.8.
        let s = try score(sample("Fruit granola"))
        #expect(s.isExact)
        #expect(abs(s.score.lowerBound - 50.5) < 0.1)
        #expect(s.gradeText == "C")
        #expect(s.undisclosed.isEmpty)
    }

    @Test func missingSugarsMakesARangeBoundedByNetCarbs() throws {
        let s = try score(sample("Fruit granola (no sugars line)"))
        #expect(!s.isExact)
        let sugars = try #require(s.components.first { $0.nutrient == .sugars })
        #expect(sugars.status == .notDisclosed)
        #expect(sugars.value == 0...64.2) // 糖質 32.1 g × 2
        #expect(s.undisclosed == [.sugars])
    }

    @Test func totalOnlyLabelLeavesSatFatAndSugarsOpen() throws {
        let s = try score(sample("Potato chips"))
        #expect(Set(s.undisclosed) == [.saturatedFat, .sugars, .fibre])
        #expect(s.bestGrade != s.worstGrade)
        // Undisclosed fibre earns nothing; it is never treated as a measured 0.
        #expect(s.components.first { $0.nutrient == .fibre }?.points == 0...0)
    }

    @Test func printedZeroNeverCostsPoints() throws {
        let s = try score(sample("Zero-calorie cola"))
        let fat = try #require(s.components.first { $0.nutrient == .fat })
        #expect(fat.status == .printedZero)
        #expect(fat.value.upperBound == 0.5)
        #expect(fat.points == 0...0)
    }

    @Test func drinksUseDrinkThresholds() throws {
        let s = try score(sample("Bottled milk tea"))
        #expect(s.isDrink)
        // 7.0 g sugars / 100 ml: (7.0 − 2.5) / (11.25 − 2.5) × 25 ≈ 12.9 points.
        let sugars = try #require(s.components.first { $0.nutrient == .sugars })
        #expect(abs(sugars.points.lowerBound + 12.857) < 0.01)
    }

    @Test func basisWithoutWeightCantBeScored() {
        var panel = sample("Potato chips")
        panel.basis = Basis(label: "1袋当たり", amount: nil, unit: nil)
        #expect(throws: HealthScorer.Failure.needsBasisAmount) { try HealthScorer.score(panel).get() }
    }

    @Test func samplesPassSanityChecks() {
        for s in SampleLabels.all {
            #expect(SanityChecks.run(s.panel).isEmpty, "\(s.name)")
        }
    }

    @Test func sanityCatchesSugarsAboveNetCarbs() {
        var panel = sample("Fruit granola")
        panel.values[.sugars] = Amount(40)
        #expect(!SanityChecks.run(panel).isEmpty)
    }
}

@Suite struct DailyValueTests {
    let dv = DailyValues.shared

    @Test func japanHasNoSugarValueSoWHOFillsIt() throws {
        let panel = SampleLabels.all[1].panel
        let pct = try #require(dv.percent(for: .sugars, amount: 11, panel: panel, sourceKey: "jp"))
        #expect(pct.fallbackSourceName == "WHO")
        #expect(pct.kind == .limit)
        #expect(abs(pct.percent - 20) < 0.01) // WHO 10% of 2,200 kcal ÷ 4 = 55 g
    }

    @Test func japanNetCarbsHasNoReference() {
        let panel = SampleLabels.all[3].panel
        #expect(dv.percent(for: .netCarbs, amount: 30, panel: panel, sourceKey: "jp") == nil)
    }

    @Test func usSaltIsConvertedToSodium() throws {
        let panel = SampleLabels.all[0].panel
        let pct = try #require(dv.percent(for: .salt, amount: 2.54, panel: panel, sourceKey: "us"))
        #expect(abs(pct.percent - 1000.0 / 2300 * 100) < 0.01)
    }

    @Test func euCarbohydrateFallbackOnlyWithoutNetCarbs() {
        let withNet = SampleLabels.all[3].panel
        let totalOnly = SampleLabels.all[0].panel
        #expect(dv.percent(for: .carbohydrate, amount: 36, panel: withNet, sourceKey: "eu") == nil)
        #expect(dv.percent(for: .carbohydrate, amount: 26, panel: totalOnly, sourceKey: "eu")?.percent == 10)
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
        let panel = try label([line(.energy, 200, "kcal"), line(.carbohydrate, 30)]).toPanel()
        #expect(panel[.fibre] == nil)
        #expect(panel[.sugars] == nil)
        #expect(panel.carbState == .totalOnly)
    }

    @Test func sodiumOnlyBecomesSalt() throws {
        let panel = try label([line(.sodium, 1.2, "g")]).toPanel()
        #expect(abs(panel[.salt]!.min - 1200 * 2.54 / 1000) < 0.001)
    }

    @Test func rangesAndZerosAreKept() throws {
        let panel = try label([line(.energy, 120, "kcal", max: 150), line(.fat, 0)]).toPanel()
        #expect(panel[.energy] == Amount(min: 120, max: 150))
        #expect(panel[.fat]?.isPrintedZero == true)
    }

    @Test func basisWithoutAmountIsNotGuessed() throws {
        var l = label([line(.fat, 3)], basis: "1袋当たり", amount: 0)
        l.netContentsAmount = 85
        let panel = try l.toPanel()
        #expect(panel.basis.amount == nil)
        #expect(panel.netContents == 85)
    }

    @Test func noPanelThrows() {
        let l = ExtractedLabel(panelFound: false, productName: "", basisText: "", basisAmount: 0, basisUnit: .g,
                               netContentsAmount: 0, lines: [], isEstimate: false)
        #expect(throws: (any Error).self) { try l.toPanel() }
    }
}

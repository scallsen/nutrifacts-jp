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
        ExtractedLabel(panelFound: true, productName: "", productNameEnglish: "", basisText: basis, basisAmount: amount, basisUnit: .g,
                       netContentsText: "", netContentsAmount: 0, netContentsUnit: .none, netContentsCount: 0, lines: lines, isEstimate: false)
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

    @Test func printedZeroIsLowInTheUKsWords() throws {
        let panel = try label([line(.fat, 0), line(.carbohydrate, 0)]).toPanel(photo: nil)
        #expect(PanelAnalysis(panel: panel, basis: .asLabelled, source: .unitedKingdom).verdict(.fat)?.text == "Low")
        // Japan publishes no such words.
        #expect(PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan).verdict(.fat) == nil)
        #expect(PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan).value(.fat)?.text == "0 g")
    }

    @Test func eachAuthorityUsesItsOwnWords() throws {
        // A 300 g bento: fat 12 g, salt 2.0 g, fibre 7 g.
        let bento = try label([line(.fat, 12), line(.salt, 2.0), line(.carbohydrate, 40), line(.fibre, 7)],
                              basis: "1食（300g）当たり", amount: 300).toPanel(photo: nil)
        func analysis(_ source: ReferenceSource) -> PanelAnalysis { PanelAnalysis(panel: bento, basis: .asLabelled, source: source) }

        // Japan, the EU and WHO: no words, no warnings.
        for source in [ReferenceSource.japan, .europeanUnion, .who] {
            #expect(analysis(source).verdict(.salt) == nil)
            #expect(analysis(source).warnings.isEmpty)
        }

        // UK: fat 4 g per 100 g is Medium; salt 0.67 g per 100 g is Medium, but 2.0 g is over 30% of 6 g in a 300 g portion.
        #expect(analysis(.unitedKingdom).verdict(.fat)?.text == "Medium")
        #expect(analysis(.unitedKingdom).verdict(.salt)?.text == "High")
        #expect(analysis(.unitedKingdom).warnings.contains { $0.title == "High in salt" })
        // Sugars aren't listed, and the 33 g of net carbs could all be sugar: 37% of 90 g in the portion.
        let maybeSugars = analysis(.unitedKingdom).warnings.first { $0.title == "May be high in sugars" }
        #expect(maybeSugars?.detail.hasPrefix("Up to ") == true)
        #expect(maybeSugars?.info == "A carbohydrate breakdown is not provided by the label, so this is an estimate.")

        // FDA: salt 2.0 / 5.84 = 34% is High; fat 12 / 78 = 15% gets no word; fibre 7 / 28 = 25% is High.
        #expect(analysis(.unitedStates).verdict(.salt)?.text == "High")
        #expect(analysis(.unitedStates).verdict(.fat) == nil)
        #expect(analysis(.unitedStates).verdict(.fibre)?.text == "High")

        // Canada: "A lot" from 15%. Its "High in" symbol for a 300 g main dish needs 30%, and leaves out fat.
        #expect(analysis(.canada).verdict(.salt)?.text == "A lot")
        #expect(analysis(.canada).verdict(.fat)?.text == "A lot") // 12 / 75 = 16%
        let canada = analysis(.canada).warnings.map(\.title)
        #expect(canada.contains("High in salt") && !canada.contains("High in fat"))
        #expect(AgencyRule.canadaHighInAt(serving: 25, isDrink: false) == 10)
        // A 25 g snack with 12 g of sugars: 12% isn't "A lot", but it needs the "High in" symbol, so the row says so too.
        let snack = try label([line(.sugars, 12), line(.carbohydrate, 15)], basis: "1袋（25g）当たり", amount: 25).toPanel(photo: nil)
        let canadaSnack = PanelAnalysis(panel: snack, basis: .asLabelled, source: .canada)
        #expect(canadaSnack.warnings.contains { $0.title == "High in sugars" })
        #expect(canadaSnack.verdict(.sugars)?.text == "High in")

        // A per 100 g label has no serving, so the FDA and Canada say nothing; the UK still does.
        let per100 = try label([line(.salt, 2.0)]).toPanel(photo: nil)
        #expect(PanelAnalysis(panel: per100, basis: .asLabelled, source: .unitedStates).verdict(.salt) == nil)
        #expect(PanelAnalysis(panel: per100, basis: .asLabelled, source: .unitedKingdom).verdict(.salt)?.text == "High")
        #expect(ReferenceSource.with(id: "uk").name == "United Kingdom")
    }

    @Test func aSmallBottleIsOneServing() throws {
        // A drink labelled per 100 ml: 6.7 g of carbohydrate, no sugars line.
        func analysis(pack: Double) throws -> PanelAnalysis {
            let l = ExtractedLabel(panelFound: true, productName: "", productNameEnglish: "", basisText: "100ml当たり", basisAmount: 100, basisUnit: .ml,
                                   netContentsText: "", netContentsAmount: pack, netContentsUnit: .ml, netContentsCount: 0,
                                   lines: [line(.energy, 27, "kcal"), line(.carbohydrate, 6.7), line(.salt, 0.1)], isEstimate: false)
            return PanelAnalysis(panel: try l.toPanel(photo: nil), basis: .asLabelled, source: .canada)
        }
        // A 450 ml bottle is one serving: up to 30 g of sugars is 30% of Canada's 100 g.
        let bottle = try analysis(pack: 450)
        #expect(bottle.serving == 450)
        #expect(bottle.warnings.first?.title == "May be high in sugars")
        #expect(bottle.warnings.first?.detail.contains("450 ml bottle") == true)
        #expect(bottle.guidanceNotice == nil)
        #expect(bottle.mayBeHigh(.sugars))
        #expect(bottle.verdict(.sugars) == nil)
        // Labels often write mL.
        let capitalL = ExtractedLabel(panelFound: true, productName: "", productNameEnglish: "", basisText: "100mL当たり", basisAmount: 100, basisUnit: .ml,
                                      netContentsText: "", netContentsAmount: 500, netContentsUnit: .ml, netContentsCount: 0,
                                      lines: [line(.carbohydrate, 6.8)], isEstimate: false)
        let mL = PanelAnalysis(panel: try capitalL.toPanel(photo: nil), basis: .asLabelled, source: .canada)
        #expect(mL.serving == 500)
        #expect(mL.warnings.first?.title == "May be high in sugars")
        // A 1 L bottle holds several servings, so there's no serving to judge.
        let large = try analysis(pack: 1000)
        #expect(large.serving == nil)
        #expect(large.guidanceNotice?.title == "No serving size")
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

    @Test @MainActor func typedPackSizeAddsTheWholePack() throws {
        // A drink labelled per 100 ml whose 500 ml 内容量 isn't in the photo.
        var l = label([line(.energy, 40, "kcal"), line(.sugars, 10)], basis: "100ml当たり")
        l.basisUnit = .ml
        var panel = try l.toPanel(photo: nil)
        #expect(!PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan).availableBases.contains(.wholePack))
        panel.setPack(amount: 500)
        let pack = PanelAnalysis(panel: panel, basis: .wholePack, source: .japan)
        #expect(pack.availableBases.contains(.wholePack))
        #expect(pack.title(for: .wholePack) == "Pack · 500 ml")
        #expect(pack.value(.energy)?.text == "200 kcal")
    }

    @Test func boxNetContentsFillsAMissingPackSize() throws {
        var l = label([line(.energy, 40, "kcal")], basis: "100ml当たり")
        l.basisUnit = .ml
        var panel = try l.toPanel(photo: nil)
        panel.apply(netContents: 500, unit: .millilitres, count: 0, printed: "500ml")
        #expect(panel.packAmount == 500)
        // It never replaces a pack size that's already known, e.g. one the user typed.
        panel.apply(netContents: 350, unit: .millilitres, count: 0, printed: "350ml")
        #expect(panel.packAmount == 500)
    }

    @Test func decodesTheWorkersIngredientsBox() throws {
        // The shape backend/src/ingredients.ts returns from /v1/ingredients-box/read.
        let json = """
        {"boxFound":true,"category":{"japanese":"調味酢","english":"seasoned vinegar"},
         "ingredients":[{"japanese":"果糖ぶどう糖液糖","english":"high-fructose corn syrup","isAdditive":false},
                        {"japanese":"酸味料","english":"acidulant","isAdditive":true}],
         "allergens":["りんご"],"netContentsText":"500ml","netContentsAmount":500,"netContentsUnit":"ml",
         "netContentsCount":0,"netContentsPrintedElsewhere":false,"date":{"japanese":"下部に記載","english":"printed below"},
         "isUseBy":false,"storage":{"japanese":"","english":""},"maker":"株式会社 ミツカン",
         "countryOfOrigin":{"japanese":"","english":""}}
        """
        let box = try JSONDecoder().decode(ExtractedIngredientsBox.self, from: Data(json.utf8))
        #expect(box.ingredients.map(\.isAdditive) == [false, true])
        #expect(box.allergens == ["りんご"])
        #expect(box.netContents?.amount == 500)
        #expect(box.netContents?.unit == .millilitres)
    }

    @Test func boxNetContentsInAnotherUnitIsIgnored() throws {
        var panel = try label([line(.fat, 3)]).toPanel(photo: nil) // per 100 g
        panel.apply(netContents: 500, unit: .millilitres, count: 0, printed: "500ml")
        #expect(panel.packAmount == nil)
    }

    @Test func boxNetContentsIsOnlySuggestedForASizelessBasis() throws {
        var panel = try label([line(.fat, 3)], basis: "1個当たり", amount: 0).toPanel(photo: nil)
        panel.apply(netContents: 120, unit: .grams, count: 6, printed: "120g（6個入）")
        #expect(panel.basisAmount == nil)
        #expect(panel.basisSuggestion == BasisSuggestion(amount: 20, unit: .grams, reason: "内容量 120g（6個入） ÷ 6"))
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

    // MARK: Pieces and packs

    /// A chocolate croissant: 1包装当り with 内容量 1個, and no weight anywhere.
    private func croissant(contents: String = "1個") -> ExtractedLabel {
        var l = label([line(.energy, 272, "kcal"), line(.protein, 3.3), line(.fat, 16.2), line(.carbohydrate, 29.0),
                       line(.netCarbs, 27.7), line(.fibre, 1.3), line(.salt, 0.4)], basis: "1包装当り", amount: 0)
        l.netContentsText = contents
        // Models read the 1 in 1個 as 1 g.
        l.netContentsAmount = 1
        l.netContentsUnit = .g
        l.netContentsCount = 1
        return l
    }

    @Test func aCountInContentsIsNotAWeight() throws {
        let panel = try croissant().toPanel(photo: nil)
        #expect(panel.basisSuggestion == nil)
        #expect(panel.packAmount == nil)
        #expect(panel.basisDescription == "per 1包装")
        #expect(panel.portion == Portion(singular: "piece", plural: "pieces", ofBasis: 1, perPack: 1))
        // A Worker deployed before netContentsText: an amount equal to the count is the same mistake.
        #expect(try croissant(contents: "").toPanel(photo: nil).basisSuggestion == nil)
        #expect(!LabelPanel.printsWeight("1個"))
        #expect(LabelPanel.printsWeight("120g（6個入）"))
        #expect(LabelPanel.printsWeight("1L"))
        #expect(LabelPanel.printsWeight("500ｍｌ"))
    }

    @Test func aPieceIsCountedWithoutItsWeight() throws {
        let panel = try croissant().toPanel(photo: nil)
        #expect(PanelAnalysis.availableBases(for: panel) == [.asLabelled])
        let one = PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan)
        #expect(one.title(for: .asLabelled) == "1 piece")
        #expect(one.value(.fat)?.text == "16.2 g")
        #expect(one.basisNote == "The label is per 1包装, the whole pack.")
        let three = PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan, count: 3)
        #expect(three.value(.energy)?.text == "816 kcal")
        #expect(three.basisDescription == "per 3 pieces")
    }

    @Test func fdaAndCanadaJudgeAPieceWithoutItsWeight() throws {
        let panel = try croissant().toPanel(photo: nil)
        let fda = PanelAnalysis(panel: panel, basis: .asLabelled, source: .unitedStates)
        #expect(fda.warnings.first?.title == "High in fat")
        #expect(fda.warnings.first?.detail == "21% of the daily value in one piece. The FDA calls 20% or more high.")
        // The rules judge one label serving, however many pieces are shown.
        #expect(PanelAnalysis(panel: panel, basis: .asLabelled, source: .unitedStates, count: 2).warnings.first?.detail == fda.warnings.first?.detail)
        let canada = PanelAnalysis(panel: panel, basis: .asLabelled, source: .canada)
        #expect(canada.warnings.map(\.title) == ["May be high in saturated fat", "May be high in sugars"])
        #expect(canada.warnings.first?.detail.contains("from 15% for most foods") == true)
        // The UK's traffic lights are per 100 g, so they need the weight.
        let uk = PanelAnalysis(panel: panel, basis: .asLabelled, source: .unitedKingdom)
        #expect(uk.warnings.isEmpty)
        #expect(uk.guidanceNotice?.title == "Traffic lights need the weight")
    }

    @Test func aWeightForAPackLabelIsThePack() throws {
        var panel = try croissant().toPanel(photo: nil)
        panel.confirmBasis(amount: 70, unit: .grams)
        #expect(panel.packAmount == 70)
        let analysis = PanelAnalysis(panel: panel, basis: .per100, source: .japan)
        #expect(analysis.availableBases == [.asLabelled, .per100])
        #expect(analysis.value(.fat)?.text == "23.1 g")
    }

    @Test func aPackLabelWithSeveralPiecesCountsPieces() throws {
        var l = label([line(.energy, 600, "kcal"), line(.fat, 30)], basis: "1包装当たり", amount: 0)
        l.netContentsText = "120g（6個入）"
        l.netContentsAmount = 120
        l.netContentsUnit = .g
        l.netContentsCount = 6
        let panel = try l.toPanel(photo: nil)
        // The label is the whole pack, so its size is the whole 内容量, not a sixth of it.
        #expect(panel.basisSuggestion == BasisSuggestion(amount: 120, unit: .grams, reason: "内容量 120 g"))
        #expect(panel.portion?.perPack == 6)
        let two = PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan, count: 2)
        #expect(two.value(.energy)?.text == "200 kcal")
        #expect(two.basisNote == "The label is per 1包装, the whole pack. The pack holds 6 pieces.")
    }

    @Test func aCountedPackAddsTheWholePack() throws {
        var l = label([line(.energy, 45, "kcal"), line(.fat, 2.5)], basis: "1個当たり", amount: 0)
        l.netContentsText = "6個"
        l.netContentsCount = 6
        let panel = try l.toPanel(photo: nil)
        #expect(panel.contentsCounter == "個")
        let pack = PanelAnalysis(panel: panel, basis: .wholePack, source: .japan)
        #expect(pack.availableBases == [.asLabelled, .wholePack])
        #expect(pack.title(for: .wholePack) == "Pack · 6 pieces")
        #expect(pack.value(.energy)?.text == "270 kcal")
        #expect(pack.basisDescription == "whole pack (6 pieces)")
        #expect(PanelAnalysis.defaultBasis(for: panel) == .wholePack)
    }

    @Test func oneBagOfAMultipackIsNotThePack() throws {
        var l = label([line(.energy, 80, "kcal")], basis: "1袋当たり", amount: 0)
        l.netContentsText = "10袋"
        l.netContentsCount = 10
        let panel = try l.toPanel(photo: nil)
        #expect(!panel.basisIsWholePack)
        #expect(panel.portion == Portion(singular: "bag", plural: "bags", ofBasis: 1, perPack: 10))
    }

    @Test func servingsComeFromTheWeights() {
        // 1食分（50g）当たり in a 400 g bag: 8 servings.
        let granola = PanelAnalysis(panel: SampleLabels.granola, basis: .asLabelled, source: .japan, count: 2)
        #expect(granola.portion?.perPack == 8)
        #expect(granola.title(for: .asLabelled) == "2 servings")
        #expect(granola.value(.energy)?.text == "440 kcal")
        #expect(granola.basisDescription == "per 2 servings (100 g)")
    }
}

@Suite struct AIAndConfigTests {
    @Test func settingsOfferAIAndAndAppleIntelligence() {
        #expect(Backend.supported == [.appleIntelligence, .aiAnd])
        // Choices saved before PCC and on-device were merged still load.
        #expect(Backend(rawValue: "privateCloudCompute") == .appleIntelligence)
        #expect(Backend(rawValue: "onDevice") == .appleIntelligence)
        #expect(Backend(rawValue: Backend.aiAnd.rawValue) == .aiAnd)
    }

    @Test func newUsersDefaultToAIAnd() {
        #expect(Backend.aiAnd.isSupported)
        #expect(Backend.defaultBackend == .aiAnd)
    }

    @Test func reasoningLevelComesFromSettings() {
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: AIAndConfig.reasoningEffortKey) }
        defaults.set("", forKey: AIAndConfig.reasoningEffortKey)
        #expect(AIAndConfig.current.reasoningEffort == nil) // "Default" lets the Worker decide
        defaults.set("medium", forKey: AIAndConfig.reasoningEffortKey)
        #expect(AIAndConfig.current.reasoningEffort == "medium")
    }

    @Test func appPointsAtTheDeployedWorker() {
        // From Config/NutriFacts.xcconfig via Info.plist.
        #expect(AIAndConfig.current.apiURL?.absoluteString == "https://nutrifacts-api.justin-garcia.workers.dev")
    }
}

@Suite struct DiagnosticsTests {
    @Test func secondsReadNaturally() {
        #expect(ScanTiming.seconds(.milliseconds(42)) == "42 ms")
        #expect(ScanTiming.seconds(.milliseconds(5_120)) == "5.1 s")
    }

    @Test func roundTripSplitsIntoServerAndNetwork() throws {
        let response = try #require(HTTPURLResponse(url: URL(string: "https://x.test")!, statusCode: 200, httpVersion: nil, headerFields: [
            "Server-Timing": "aiand;dur=5000, total;dur=5100",
            "X-AIAnd-Usage": "promptTokens=2400; completionTokens=300",
            "X-Reasoning-Effort": "low",
        ]))
        let details = AIAndReader.details(response: response, encode: .milliseconds(30), jpegBytes: 300 * 1024,
                                          bodyBytes: 400 * 1024, roundTrip: .milliseconds(6_000))
        let byName = Dictionary(uniqueKeysWithValues: details.map { ($0.name, $0.value) })
        #expect(byName["Upload"] == "400 KB (JPEG 300 KB)")
        #expect(byName["Server"] == "5.1 s (AI& 5.0 s)")
        #expect(byName["Network"] == "0.9 s")
        #expect(byName["Tokens"] == "promptTokens=2400; completionTokens=300")
        #expect(byName["Reasoning"] == "low")
    }

    @Test @MainActor func logExportHasSettingsAndScans() async {
        let text = await DiagnosticsLog(history: []).text()
        #expect(text.contains("Read labels with:"))
        #expect(text.contains("Scans this session"))
        #expect(text.contains("Log (this session)"))
    }
}

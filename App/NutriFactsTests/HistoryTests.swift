import Foundation
import Testing
@testable import NutriFacts

@MainActor
@Suite struct HistoryTests {
    private func tempStore() -> ScanStore {
        ScanStore(folder: FileManager.default.temporaryDirectory.appending(path: "ScanStoreTests-\(UUID().uuidString)"))
    }

    @Test func storeKeepsScansAndPhotosAcrossLoads() throws {
        let store = tempStore()
        defer { store.deleteAll() }
        var panel = SampleLabels.granola
        panel.photo = Data([1, 2, 3])
        panel.productName = TranslatedText(japanese: "フルグラ", english: "Frugra")
        let older = Scan(date: .now.addingTimeInterval(-3600), panel: SampleLabels.all[0])
        var newer = Scan(date: .now, panel: panel, readBy: .aiAnd)
        newer.boxPhoto = Data([4, 5])
        store.save(older)
        store.save(newer)

        let loaded = store.load()
        #expect(loaded.map(\.id) == [newer.id, older.id])
        let first = try #require(loaded.first)
        #expect(first == newer)
        #expect(first.panel.photo == Data([1, 2, 3]))
        #expect(first.boxPhoto == Data([4, 5]))
        #expect(first.title == "Frugra")

        store.delete(older.id)
        #expect(store.load().map(\.id) == [newer.id])
    }

    @Test func exportZipsEveryScanWithItsFrameAndReading() throws {
        let store = tempStore()
        defer { store.deleteAll() }
        let label = try JSONDecoder().decode(ExtractedLabel.self, from: Data("""
        {"panelFound":true,"productName":"","productNameEnglish":"","basisText":"100g当たり","basisAmount":100,"basisUnit":"g",
         "netContentsAmount":0,"netContentsUnit":"none","netContentsCount":0,"isEstimate":false,"lines":[]}
        """.utf8))
        var scan = Scan(date: .now, panel: SampleLabels.granola, reading: label)
        scan.framePhoto = Data([7, 7])
        store.save(scan)
        let loaded = try #require(store.load().first)
        #expect(loaded.framePhoto == Data([7, 7]))
        #expect(loaded.reading == label)

        let zip = try store.export()
        let data = try Data(contentsOf: zip)
        #expect(data.starts(with: [0x50, 0x4B, 0x03, 0x04])) // "PK", a zip
        #expect(data.count > 100)
    }

    @Test func savingAgainUpdatesTheScan() throws {
        let store = tempStore()
        defer { store.deleteAll() }
        var scan = Scan(date: .now, panel: SampleLabels.granola)
        store.save(scan)
        scan.panel.setPack(amount: 400)
        store.save(scan)
        #expect(try #require(store.load().first).panel.packAmount == 400)
    }

    @Test func labelFromAnOlderWorkerStillDecodes() throws {
        let json = """
        {"panelFound":true,"productName":"ポテトチップス","basisText":"1袋（60g）当たり","basisAmount":60,"basisUnit":"g",
         "netContentsAmount":0,"netContentsUnit":"none","netContentsCount":0,"isEstimate":false,
         "lines":[{"nutrient":"energy","printedName":"熱量","minValue":336,"maxValue":336,"unit":"kcal"}]}
        """
        let label = try JSONDecoder().decode(ExtractedLabel.self, from: Data(json.utf8))
        #expect(label.productNameEnglish == "")
        let panel = try label.toPanel(photo: nil)
        #expect(panel.productName == TranslatedText(japanese: "ポテトチップス", english: ""))
        #expect(Scan(date: .now, panel: panel).title == "ポテトチップス")
    }

    @Test func titleFallsBackToTheFoodType() throws {
        var panel = SampleLabels.granola
        panel.nickname = ""
        var scan = Scan(date: .now, panel: panel)
        #expect(scan.title == nil)
        scan.box = ExtractedIngredientsBox(boxFound: true, category: TranslatedText(japanese: "清涼飲料水", english: "Soft drink"),
                                           ingredients: [], allergens: [], netContentsText: "", netContentsAmount: 0,
                                           netContentsUnit: .none, netContentsCount: 0, netContentsPrintedElsewhere: false,
                                           date: TranslatedText(japanese: "", english: ""), isUseBy: false,
                                           storage: TranslatedText(japanese: "", english: ""), maker: "",
                                           countryOfOrigin: TranslatedText(japanese: "", english: ""))
        #expect(scan.title == "Soft drink")
    }

    @Test func spotsTheIngredientsBoxInAPhotosText() {
        #expect(CameraEngine.isIngredientsBox(["名称 スナック菓子", "原材料名 じゃがいも（国産）、植物油"]))
        #expect(CameraEngine.isIngredientsBox(["名称 清涼飲料水", "内容量 500ml", "賞味期限 キャップに記載"]))
        // A panel with net contents printed beside it isn't a box.
        #expect(!CameraEngine.isIngredientsBox(["栄養成分表示 1袋（60g）当たり", "熱量 336kcal", "内容量 60g"]))
    }

    @Test func opensOnTheWholePackWhenItsSizeIsKnown() {
        var panel = SampleLabels.granola
        panel.packAmount = nil
        #expect(PanelAnalysis.defaultBasis(for: panel) == .asLabelled)
        panel.setPack(amount: 400)
        #expect(PanelAnalysis.defaultBasis(for: panel) == .wholePack)
        let analysis = PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan)
        #expect(analysis.basisNote == "The maker's serving size, not the whole pack.")
        panel.setPack(amount: panel.basisAmount!)
        #expect(PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan).basisNote == "The label's amount is the whole pack.")
    }

    @Test func groupsScansByDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12)))
        let scans = [0.0, -1, -25, -26, -24 * 9].map { Scan(date: now.addingTimeInterval($0 * 3600), panel: SampleLabels.granola) }
        let days = HistoryView.days(scans, calendar: calendar)
        #expect(days.map(\.scans.count) == [2, 2, 1])
        #expect(HistoryView.title(for: days[0].day, now: now, calendar: calendar) == "Today")
        #expect(HistoryView.title(for: days[1].day, now: now, calendar: calendar) == "Yesterday")
    }
}

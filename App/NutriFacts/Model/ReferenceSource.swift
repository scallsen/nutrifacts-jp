import Foundation

/// How an authority describes an amount, in its own words. Japan, the EU and WHO publish no such words,
/// so their results show only the %.
enum AgencyRule: Sendable {
    /// UK front-of-pack guidance (DHSC and FSA, 2016): Low, Medium or High per 100 g/ml for fat,
    /// saturates, sugars and salt, and High for a portion over 100 g (150 ml) with more than 30% of the
    /// reference intake.
    case uk
    /// FDA: 5% DV or less per serving is low, 20% or more is high.
    case fda
    /// Health Canada: 5% DV or less per serving is "a little", 15% or more is "a lot". Separately, the
    /// "High in" front-of-pack symbol for saturated fat, sugars and sodium.
    case healthCanada

    /// The words on a nutrient row.
    var lowWord: String { self == .healthCanada ? "A little" : "Low" }
    var highWord: String { self == .healthCanada ? "A lot" : "High" }

    /// FDA and Canada judge the % of the daily value in one serving.
    var percentBands: (low: Double, high: Double)? {
        switch self {
        case .uk: nil
        case .fda: (5, 20)
        case .healthCanada: (5, 15)
        }
    }

    /// The UK's portion rule covers portions over 100 g (150 ml).
    static func ukPortionApplies(serving: Double, isDrink: Bool) -> Bool { serving > (isDrink ? 150 : 100) }

    /// Canada's "High in" threshold. Its rule uses the regulated reference amount for the food; the
    /// label's serving stands in for it, and any food serving of 200 g or more counts as a main dish.
    static func canadaHighInAt(serving: Double, isDrink: Bool) -> Double {
        serving <= 30 ? 10 : !isDrink && serving >= 200 ? 30 : 15
    }
}

/// Daily reference values the % is calculated against.
/// Placeholder: these mirror data/daily-values.json by hand and aren't loaded from it yet.
struct ReferenceSource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Flag image in the asset catalog. `nil` shows a globe.
    let flag: String?
    /// The document the values come from.
    let title: String
    /// Who it applies to and the reference energy.
    let detail: String
    /// Used in footers: "% of Japan’s daily values (adults, 2,200 kcal)."
    let summary: String
    /// Where this standard doesn't map one-to-one onto a Japanese label.
    let note: String
    let referenceKcal: Double
    /// How this authority describes amounts. Japan, the EU and WHO have no such words.
    let rule: AgencyRule?
    /// Salt is stored as grams of salt (sodium values converted with × 2.54).
    let values: [NutrientKey: Double]
    let searchTerms: [String]

    var isWHO: Bool { id == "who" }

    /// EU and UK "carbohydrate" leaves out fibre, so it's compared with net carbs.
    var carbohydrateExcludesFibre: Bool { id == "eu" || id == "uk" }

    static let japan = ReferenceSource(
        id: "jp", name: "Japan", flag: "Flag-jp", title: "Nutrient Reference Values for Labelling (2025)",
        detail: "Adults 18+ · 2,200 kcal",
        summary: "Japan’s daily values (adults, 2,200 kcal)",
        note: "Matches the label exactly. No sugars value, so WHO’s is used.",
        referenceKcal: 2200, rule: nil,
        values: [.energy: 2200, .protein: 85, .fat: 70, .saturatedFat: 17, .carbohydrate: 320, .fibre: 20, .salt: 7.0],
        searchTerms: ["japan", "日本", "nihon", "nippon"])

    static let who = ReferenceSource(
        id: "who", name: "World Health Organization", flag: nil, title: "Healthy Diet Guidelines",
        detail: "Global · daily limits and targets · 2,000 kcal",
        summary: "WHO daily limits (2,000 kcal)",
        note: "Limits and targets, not reference amounts. No energy, protein or carbohydrate values.",
        referenceKcal: 2000, rule: nil, values: [:],
        searchTerms: ["world health organization", "who", "global", "international", "other"])

    static let europeanUnion = ReferenceSource(
        id: "eu", name: "European Union", flag: "Flag-eu", title: "Reference Intakes (Regulation 1169/2011)",
        detail: "All 27 EU countries · adults · 2,000 kcal",
        summary: "EU reference intakes (2,000 kcal)",
        note: "No fibre value, so WHO’s is used. Carbohydrate is compared as net carbs.",
        referenceKcal: 2000, rule: nil,
        values: [.energy: 2000, .protein: 50, .fat: 70, .saturatedFat: 20, .carbohydrate: 260, .sugars: 90, .salt: 6],
        searchTerms: ["europe", "austria", "belgium", "bulgaria", "croatia", "cyprus", "czechia", "czech republic",
                      "denmark", "estonia", "finland", "france", "germany", "greece", "hungary", "ireland", "italy",
                      "latvia", "lithuania", "luxembourg", "malta", "netherlands", "poland", "portugal", "romania",
                      "slovakia", "slovenia", "spain", "sweden"])

    static let unitedKingdom = ReferenceSource(
        id: "uk", name: "United Kingdom", flag: "Flag-gb", title: "Reference Intakes (retained Regulation 1169/2011)",
        detail: "England, Scotland, Wales, Northern Ireland · adults · 2,000 kcal",
        summary: "UK reference intakes (2,000 kcal)",
        note: "Same values as the EU. No fibre value, so WHO’s is used. Carbohydrate is compared as net carbs.",
        referenceKcal: 2000, rule: .uk,
        values: [.energy: 2000, .protein: 50, .fat: 70, .saturatedFat: 20, .carbohydrate: 260, .sugars: 90, .salt: 6],
        searchTerms: ["united kingdom", "uk", "britain", "great britain", "england", "scotland", "wales", "northern ireland"])

    static let unitedStates = ReferenceSource(
        id: "us", name: "United States", flag: "Flag-us", title: "Daily Values (21 CFR 101.9)",
        detail: "Adults and children 4+ · 2,000 kcal",
        summary: "US daily values (2,000 kcal)",
        note: "The sugar value is for added sugars only, so WHO’s is used. Salt is compared as sodium.",
        referenceKcal: 2000, rule: .fda,
        values: [.energy: 2000, .protein: 50, .fat: 78, .saturatedFat: 20, .carbohydrate: 275, .fibre: 28, .salt: 5.84],
        searchTerms: ["united states", "usa", "america", "us"])

    static let canada = ReferenceSource(
        id: "ca", name: "Canada", flag: "Flag-ca", title: "Table of Daily Values (2022)",
        detail: "Ages 4+ · no energy value",
        summary: "Canada’s daily values",
        note: "No energy, protein or carbohydrate values. Saturated fat includes trans fat.",
        referenceKcal: 2000, rule: .healthCanada,
        values: [.fat: 75, .saturatedFat: 20, .sugars: 100, .fibre: 28, .salt: 5.84],
        searchTerms: ["canada", "canadian"])

    static let all = [japan, who, europeanUnion, unitedKingdom, unitedStates, canada]

    static func with(id: String) -> ReferenceSource { all.first { $0.id == id } ?? japan }

    /// WHO limits and targets, scaled to this source's reference energy.
    func whoValue(_ key: NutrientKey) -> Double? {
        switch key {
        case .sugars: referenceKcal * 0.10 / 4
        case .saturatedFat: referenceKcal * 0.10 / 9
        case .fat: referenceKcal * 0.30 / 9
        case .salt: 2000 * 2.54 / 1000
        case .fibre: 25
        default: nil
        }
    }

    /// The amount a line is compared with: this source first, then WHO.
    func reference(for key: NutrientKey) -> (amount: Double, fromWHO: Bool)? {
        if isWHO { return whoValue(key).map { ($0, false) } }
        if let value = values[key] { return (value, false) }
        return whoValue(key).map { ($0, true) }
    }

    /// Search by name or by a country the source covers. Returns the matched country, if any.
    func matches(_ query: String) -> (Bool, matchedCountry: String?) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty || name.lowercased().contains(q) { return (true, nil) }
        if let hit = searchTerms.first(where: { $0.hasPrefix(q) }) { return (true, id == "eu" || id == "uk" ? hit.capitalized : nil) }
        return (false, nil)
    }
}

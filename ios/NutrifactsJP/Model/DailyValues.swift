import Foundation

/// Decodes `data/daily-values.json`, the source of truth for every % the app shows (rule 7).
nonisolated struct DailyValues: Decodable, Sendable {
    struct Version: Decodable, Sendable { var displayName: String }

    struct Entry: Decodable, Sendable {
        var amount: Double?
        var unit: String?
        var match: String
        var kind: String?
        var percentOfEnergy: Double?
        var kcalPerGram: Double?
        var fallbackFor: String?
        var note: String?
    }

    struct Source: Decodable, Sendable {
        var name: String
        var version: Version
        var referenceEnergyKcal: Double?
        var dailyValues: [String: Entry]
    }

    var defaultSource: String
    var fallbackSource: String
    var sources: [String: Source]

    static let shared: DailyValues = {
        guard let url = Bundle.main.url(forResource: "daily-values", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(DailyValues.self, from: data)
        else { fatalError("daily-values.json is missing from the app bundle") }
        return decoded
    }()

    /// Sources the user can choose, in display order. WHO is only a fallback.
    var selectableSourceKeys: [String] { ["jp", "eu", "us", "ca"].filter { sources[$0] != nil } }
}

/// One row's %DV, or the reason there isn't one.
nonisolated struct DailyValuePercent: Hashable, Sendable {
    enum Kind: String, Sendable { case reference, limit, target }
    var percent: Double
    var kind: Kind
    /// Set when WHO filled the gap, e.g. "WHO".
    var fallbackSourceName: String?
    var footnote: String?

    var phrase: String {
        switch kind {
        case .reference: "of daily value"
        case .limit: "of daily limit"
        case .target: "of daily target"
        }
    }
}

extension DailyValues {
    /// %DV for one label line, following the lookup order in docs/daily-values.md.
    /// Returns nil for "No reference".
    func percent(for nutrient: Nutrient, amount: Double, panel: NutritionPanel, sourceKey: String) -> DailyValuePercent? {
        guard let source = sources[sourceKey] else { return nil }

        if let entry = source.dailyValues[nutrient.rawValue], entry.match != "none" {
            // A `fallback` entry only applies when the line it stands in for is missing (EU 炭水化物 → 糖質).
            if entry.match == "fallback", let target = entry.fallbackFor.flatMap(Nutrient.init(rawValue:)), panel[target] != nil {
                return nil
            }
            if let pct = compute(entry, nutrient: nutrient, amount: amount, energyKcal: source.referenceEnergyKcal) {
                let footnote = (entry.match == "exact" || entry.match == "converted") ? nil : entry.note
                return DailyValuePercent(percent: pct, kind: DailyValuePercent.Kind(rawValue: entry.kind ?? "reference") ?? .reference,
                                         fallbackSourceName: nil, footnote: footnote)
            }
        }

        guard let who = sources[fallbackSource], let entry = who.dailyValues[nutrient.rawValue], entry.match != "none",
              let pct = compute(entry, nutrient: nutrient, amount: amount, energyKcal: source.referenceEnergyKcal ?? 2000)
        else { return nil }
        return DailyValuePercent(percent: pct, kind: DailyValuePercent.Kind(rawValue: entry.kind ?? "reference") ?? .reference,
                                 fallbackSourceName: "WHO", footnote: entry.match == "exact" ? nil : entry.note)
    }

    private func compute(_ entry: Entry, nutrient: Nutrient, amount: Double, energyKcal: Double?) -> Double? {
        var reference = entry.amount
        if reference == nil, let pctEnergy = entry.percentOfEnergy, let kcalPerGram = entry.kcalPerGram {
            reference = (energyKcal ?? 2000) * pctEnergy / 100 / kcalPerGram
        }
        guard let reference, reference > 0 else { return nil }
        var value = amount
        if nutrient == .salt, entry.unit == "mg" {
            value = NutritionPanel.sodiumMg(fromSalt: amount)
        }
        return value / reference * 100
    }
}

import Foundation

/// The label lines the app understands. Raw values match the keys in `data/daily-values.json`.
nonisolated enum Nutrient: String, Codable, CaseIterable, Sendable {
    case energy, protein, fat, saturatedFat, carbohydrate, netCarbs, sugars, fibre, salt

    var japanese: String {
        switch self {
        case .energy: "熱量"
        case .protein: "たんぱく質"
        case .fat: "脂質"
        case .saturatedFat: "飽和脂肪酸"
        case .carbohydrate: "炭水化物"
        case .netCarbs: "糖質"
        case .sugars: "糖類"
        case .fibre: "食物繊維"
        case .salt: "食塩相当量"
        }
    }

    var english: String {
        switch self {
        case .energy: "Energy"
        case .protein: "Protein"
        case .fat: "Fat"
        case .saturatedFat: "Saturated fat"
        case .carbohydrate: "Carbohydrate"
        case .netCarbs: "Net carbs"
        case .sugars: "Sugars"
        case .fibre: "Fibre"
        case .salt: "Salt"
        }
    }

    var unit: String { self == .energy ? "kcal" : "g" }

    /// Indent level in the label tree ("of which" lines).
    var depth: Int {
        switch self {
        case .saturatedFat, .netCarbs, .fibre: 1
        case .sugars: 2
        default: 0
        }
    }

    /// A printed "0" means below this amount per 100 g / 100 ml (spec §7).
    var zeroThresholdPer100: Double {
        switch self {
        case .energy: 5
        case .saturatedFat: 0.1
        case .salt: 5 * 2.54 / 1000 // sodium < 5 mg
        default: 0.5
        }
    }
}

/// One printed value. A missing line is represented by the *absence* of an `Amount`, never by 0.
nonisolated struct Amount: Codable, Hashable, Sendable {
    var min: Double
    var max: Double
    /// True when the label printed "0", which only means "below the zero threshold".
    var isPrintedZero: Bool = false

    init(_ value: Double) { min = value; max = value }
    init(min: Double, max: Double) { self.min = min; self.max = max }

    var isRange: Bool { min != max }
    var midpoint: Double { (min + max) / 2 }

    func scaled(by factor: Double) -> Amount {
        var copy = Amount(min: min * factor, max: max * factor)
        copy.isPrintedZero = isPrintedZero
        return copy
    }
}

nonisolated enum BasisUnit: String, Codable, Sendable { case g, ml }

/// What amount the printed numbers describe (食品単位). There's no standard serving size.
nonisolated struct Basis: Codable, Hashable, Sendable {
    /// As printed, e.g. "1袋（60g）当たり".
    var label: String
    /// Weight or volume the basis refers to, if known.
    var amount: Double?
    var unit: BasisUnit?

    var isDrink: Bool { unit == .ml }

    /// Factor that converts label values to per 100 g / 100 ml. Nil when the weight is unknown.
    var per100Factor: Double? {
        guard let amount, amount > 0 else { return nil }
        return 100 / amount
    }

    var per100Label: String { isDrink ? "per 100 ml" : "per 100 g" }
}

/// Which carbohydrate lines a label discloses. See docs/ui-domain-context.md §3.
nonisolated enum CarbState: String, Codable, Sendable {
    case totalOnly = "A", sugarsOnly = "B", splitNoSugars = "C", full = "D"
}

nonisolated struct NutritionPanel: Codable, Hashable, Sendable {
    var productName: String?
    var basis: Basis
    var values: [Nutrient: Amount]
    var isEstimate: Bool
    /// Net contents (内容量), when visible elsewhere on the pack.
    var netContents: Double?

    subscript(_ n: Nutrient) -> Amount? { values[n] }

    var carbState: CarbState {
        let hasSplit = values[.netCarbs] != nil || values[.fibre] != nil
        let hasSugars = values[.sugars] != nil
        switch (hasSplit, hasSugars) {
        case (false, false): return .totalOnly
        case (false, true): return .sugarsOnly
        case (true, false): return .splitNoSugars
        case (true, true): return .full
        }
    }

    /// Values per 100 g / 100 ml. A printed "0" becomes 0 … threshold (rule 4).
    func per100() -> [Nutrient: Amount]? {
        guard let factor = basis.per100Factor else { return nil }
        var out: [Nutrient: Amount] = [:]
        for (n, a) in values {
            if a.isPrintedZero {
                var zero = Amount(min: 0, max: n.zeroThresholdPer100)
                zero.isPrintedZero = true
                out[n] = zero
            } else {
                out[n] = a.scaled(by: factor)
            }
        }
        return out
    }
}

extension NutritionPanel {
    /// Sodium mg from salt g (rule 5). Approximate, because salt is rounded to 0.1 g.
    static func sodiumMg(fromSalt g: Double) -> Double { g * 1000 / 2.54 }
}

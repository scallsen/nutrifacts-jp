import Foundation

/// The lines of a Japanese nutrition panel (栄養成分表示) the app understands.
/// See docs/ui-domain-context.md for what each one means.
enum NutrientKey: String, CaseIterable, Identifiable, Codable, CodingKeyRepresentable, Sendable {
    case energy, protein, fat, saturatedFat, carbohydrate, netCarbs, sugars, fibre, salt

    var id: String { rawValue }

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

    var unit: String { self == .energy ? "kcal" : "g" }

    /// A label may print "0" when the amount per 100 g/ml is below this.
    var zeroThreshold: Double {
        switch self {
        case .energy: 5
        case .saturatedFat: 0.1
        case .salt: 0.0127
        default: 0.5
        }
    }
}

enum NumberFormat {
    /// Formats an amount the way the label would: whole kcal, otherwise up to one or two decimals.
    static func amount(_ value: Double, _ key: NutrientKey) -> String {
        if key == .energy || value >= 100 { return String(Int(value.rounded())) }
        let digits = value >= 0.1 || value == 0 ? 1 : 2
        var text = String(format: "%.\(digits)f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func percent(_ value: Double) -> String {
        if value == 0 { return "0%" }
        if value < 1 { return "<1%" }
        return "\(Int(value.rounded()))%"
    }
}

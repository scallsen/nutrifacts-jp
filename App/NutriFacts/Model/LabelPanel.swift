import Foundation

enum PackUnit: String, Sendable {
    case grams = "g"
    case millilitres = "ml"

    var isDrink: Bool { self == .millilitres }
}

/// What a scan reads off the pack: the panel exactly as printed, plus nearby text.
struct LabelPanel: Identifiable, Hashable, Sendable {
    enum Layout: Sendable { case table, inline }

    let id = UUID()
    /// Only the mocks know the product. A real scan doesn't.
    var nickname: String
    var basisJapanese: String
    /// Grams or ml the printed values describe. Nil when the label doesn't say (e.g. 1個当たり),
    /// until the user confirms it. Without it nothing can be put per 100 g, so there's no score.
    var basisAmount: Double?
    var basisDescription: String
    var basisShort: String
    /// Whole-pack weight, when known.
    var packAmount: Double?
    var packShort: String
    var unit: PackUnit
    /// Values as printed, e.g. "21.6". A missing key means the line isn't on the label.
    var printed: [NutrientKey: String]
    var isEstimate = false
    var layout: Layout = .table
    /// Lines printed together as one zero row, e.g. たんぱく質・脂質 0g.
    var groupedZeros: [NutrientKey] = []
    /// A claim from the front of the pack. Only present when it was in the frame.
    var frontClaim: String?
    var ingredients: String
    var packColors: [UInt32]
    /// The screenshot or photo a real scan was read from. Nil for the mock samples.
    var photo: Data? = nil

    /// A likely size for a basis printed without one, worked out from 内容量. Shown for the user to confirm, never applied on its own.
    var basisSuggestion: BasisSuggestion? = nil

    func number(_ key: NutrientKey) -> Double? { printed[key].flatMap(Double.init) }

    /// The basis as printed without its 当たり, e.g. "1個".
    var basisUnitName: String {
        basisJapanese.replacingOccurrences(of: "当たり", with: "").replacingOccurrences(of: "あたり", with: "")
    }

    /// Sets the size of a basis printed without one, once the user has confirmed it.
    mutating func confirmBasis(amount: Double, unit: PackUnit) {
        self.unit = unit
        basisAmount = amount
        let text = "\(NumberFormat.amount(amount, .protein)) \(unit.rawValue)"
        basisDescription = "per \(basisUnitName) (\(text))"
        basisShort = "\(basisUnitName) · \(text)"
        basisSuggestion = nil
    }

    /// Sets the whole-pack size (内容量) the user typed, usually printed away from the panel.
    mutating func setPack(amount: Double) {
        packAmount = amount
        packShort = "Pack · \(NumberFormat.amount(amount, .protein)) \(unit.rawValue)"
    }
}

struct BasisSuggestion: Hashable, Sendable {
    var amount: Double
    var unit: PackUnit
    /// How it was worked out, e.g. "内容量 350 ml" or "内容量 120 g ÷ 6".
    var reason: String
}

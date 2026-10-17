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
    var basisAmount: Double
    var basisDescription: String
    var basisShort: String
    var packAmount: Double
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

    func number(_ key: NutrientKey) -> Double? { printed[key].flatMap(Double.init) }
}

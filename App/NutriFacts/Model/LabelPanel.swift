import Foundation

enum PackUnit: String, Codable, Sendable {
    case grams = "g"
    case millilitres = "ml"

    var isDrink: Bool { self == .millilitres }
}

/// What a scan reads off the pack: the panel exactly as printed, plus nearby text.
struct LabelPanel: Identifiable, Hashable, Codable, Sendable {
    enum Layout: Codable, Sendable { case table, inline }

    var id = UUID()
    /// The sample labels' names. A real scan's name is `productName`.
    var nickname: String
    /// The product name on the pack, with an English translation. Nil when it wasn't in the photo.
    var productName: TranslatedText? = nil
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

    /// How many pieces 内容量 says the pack holds, e.g. 6 for 120g（6個入） or 1 for 1個. Nil when it doesn't say.
    var contentsCount: Int? = nil
    /// The counter printed with that count, e.g. 個 or 袋. Nil when it wasn't read.
    var contentsCounter: String? = nil

    func number(_ key: NutrientKey) -> Double? { printed[key].flatMap(Double.init) }

    /// The basis as printed without its 当たり, e.g. "1個".
    var basisUnitName: String { Self.withoutPer(basisJapanese) }

    /// "1個当たり" → "1個". Labels also print 当り and あたり.
    static func withoutPer(_ text: String) -> String {
        text.replacingOccurrences(of: "当たり", with: "").replacingOccurrences(of: "当り", with: "")
            .replacingOccurrences(of: "あたり", with: "")
    }

    /// 100ml当たり, 100mL当たり, 製品100g当たり and the like.
    var isPer100: Bool {
        let basis = (basisJapanese.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? basisJapanese)
            .lowercased().replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "^(製品|本品|商品)", with: "", options: .regularExpression)
        return basis.hasPrefix("100\(unit.rawValue)")
    }

    // MARK: Pieces and packs

    /// The count and counter the basis starts with: 1個 → (1, 個), 2枚（30g） → (2, 枚), 1食分 → (1, 食).
    private var basisCount: (count: Int, counter: String)? {
        // 本品1袋当たり: the same prefixes `isPer100` drops.
        let basis = basisUnitName.replacingOccurrences(of: "^\\s*(製品|本品|商品)", with: "", options: .regularExpression)
        guard let match = basis.firstMatch(of: /^\s*([0-9０-９]+)\s*([^0-9０-９\s（(]+)/) else { return nil }
        let counter = Self.normalisedCounter(String(match.2))
        guard let count = Self.integer(match.1), count > 0, !["g", "ｇ", "ml", "mL", "ｍｌ"].contains(counter) else { return nil }
        return (count, counter)
    }

    /// Counters for a whole pack. 1袋当たり is the whole bag, unless 内容量 says the pack holds several bags.
    private static let packCounters: Set<String> = ["包装", "パック", "パッケージ", "容器", "袋", "箱", "缶", "瓶", "びん", "カップ"]

    /// True when the label's values are for the whole pack: 1包装当たり, 1袋当たり, or a size that matches 内容量.
    var basisIsWholePack: Bool {
        if let basisAmount, let packAmount { return basisAmount == packAmount }
        guard let basis = basisCount, basis.count == 1, Self.packCounters.contains(basis.counter) else { return false }
        return !((contentsCount ?? 0) > 1 && contentsCounter == basis.counter)
    }

    /// What the amount can be counted in, e.g. pieces of a label printed per 1個. Nil for a label per 100 g/ml,
    /// whose amount is a weight.
    var portion: Portion? {
        guard !isPer100 else { return nil }
        let basis = basisCount
        let pieces = contentsCount ?? 0
        if basisIsWholePack {
            // 1包装当たり with 内容量 6個入: one piece is a sixth of the label's amount.
            if pieces > 1 {
                return Portion(counter: contentsCounter ?? "個", isDrink: unit.isDrink, ofBasis: 1 / Double(pieces), perPack: pieces)
            }
            // 1包装当たり with 内容量 1個: the pack is one piece.
            return Portion(counter: pieces == 1 ? contentsCounter ?? basis?.counter : basis?.counter, isDrink: unit.isDrink,
                           ofBasis: 1, perPack: 1)
        }
        // 2枚当たり: one piece is half the label's amount.
        let inBasis = basis?.count ?? 1
        var perPack: Int?
        if pieces > 0, contentsCounter == nil || contentsCounter == basis?.counter {
            perPack = pieces
        } else if let basisAmount, let packAmount {
            let count = packAmount / basisAmount * Double(inBasis)
            if count >= 1, abs(count - count.rounded()) < 0.05 { perPack = Int(count.rounded()) }
        }
        return Portion(counter: basis?.counter, isDrink: unit.isDrink, ofBasis: 1 / Double(inBasis), perPack: perPack)
    }

    /// 食分 → 食, 回分 → 回.
    private static func normalisedCounter(_ counter: String) -> String {
        counter.count > 1 && counter.hasSuffix("分") ? String(counter.dropLast()) : counter
    }

    /// Half-width or full-width digits as a number.
    private static func integer(_ digits: Substring) -> Int? {
        Int(String(digits).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? String(digits))
    }

    /// The counter in 内容量 as printed: 120g（6個入） → 個, 10袋入 → 袋. Nil when there's no count.
    static func contentsCounter(in text: String) -> String? {
        guard let match = text.firstMatch(of: /[0-9０-９]+\s*(個|枚|本|袋|食分|食|粒|切れ|包|パック|カップ|缶|箱|コ|ケ|ヶ|人前|杯)/) else { return nil }
        return normalisedCounter(String(match.1))
    }

    /// True when 内容量 as printed has a weight or volume (120g, 1L, 500ｍｌ), not just a count (1個).
    static func printsWeight(_ text: String) -> Bool {
        text.range(of: #"[0-9０-９.．]+\s*(g|ｇ|kg|ｋｇ|ml|ｍｌ|l|ℓ|ｌ|グラム|キログラム|ミリリットル|リットル)"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Sets the size of a basis printed without one, once the user has confirmed it.
    mutating func confirmBasis(amount: Double, unit: PackUnit) {
        self.unit = unit
        basisAmount = amount
        let text = "\(NumberFormat.amount(amount, .protein)) \(unit.rawValue)"
        basisDescription = "per \(basisUnitName) (\(text))"
        basisShort = "\(basisUnitName) · \(text)"
        basisSuggestion = nil
        // 1包装当たり: the weight of the basis is the weight of the pack.
        if packAmount == nil, basisIsWholePack { setPack(amount: amount) }
    }

    /// Uses the count in 内容量 read from the ingredients box (6個入, 1個), unless the panel's photo gave one.
    mutating func apply(contentsCount count: Int, printed: String) {
        guard contentsCount == nil, count > 0 else { return }
        contentsCount = count
        contentsCounter = Self.contentsCounter(in: printed)
    }

    /// Uses 内容量 read from the ingredients box. Sets the pack size when the basis has one and no pack size
    /// is known yet (it never replaces one), or offers it as the size of a basis printed without one.
    mutating func apply(netContents amount: Double, unit contentsUnit: PackUnit, count: Int, printed: String) {
        if basisAmount != nil {
            if packAmount == nil, contentsUnit == unit { setPack(amount: amount) }
        } else if basisSuggestion == nil {
            // A label per pack is the whole 内容量, even when the pack holds several pieces.
            let pieces = basisIsWholePack ? 1 : max(count, 1)
            let text = "内容量 \(printed)"
            basisSuggestion = BasisSuggestion(amount: amount / Double(pieces), unit: contentsUnit,
                                              reason: pieces > 1 ? "\(text) ÷ \(pieces)" : text)
        }
    }

    /// Sets the whole-pack size (内容量), usually printed away from the panel.
    mutating func setPack(amount: Double) {
        packAmount = amount
        packShort = "Pack · \(NumberFormat.amount(amount, .protein)) \(unit.rawValue)"
    }
}

/// One step of the amount: a piece, serving or pack, and how it relates to the label's basis.
struct Portion: Hashable, Sendable {
    var singular: String
    var plural: String
    /// How much of the label's basis one is: 1, or 1/6 for a piece of a label printed per pack of 6.
    var ofBasis: Double
    /// How many make the whole pack, when the label or 内容量 says.
    var perPack: Int?

    init(singular: String, plural: String, ofBasis: Double, perPack: Int?) {
        self.singular = singular
        self.plural = plural
        self.ofBasis = ofBasis
        self.perPack = perPack
    }

    /// Named after the Japanese counter: 個 is a piece, 袋 a bag, 食 a serving. A serving when there's none.
    init(counter: String?, isDrink: Bool, ofBasis: Double, perPack: Int?) {
        let names: (String, String) = switch counter ?? "" {
        case "個", "コ", "ケ", "ヶ", "粒", "枚", "切れ", "片": ("piece", "pieces")
        case "本": isDrink ? ("bottle", "bottles") : ("piece", "pieces")
        case "袋": ("bag", "bags")
        case "包": ("packet", "packets")
        case "缶": ("can", "cans")
        case "カップ", "杯": ("cup", "cups")
        case "箱": ("box", "boxes")
        case "包装", "パック", "パッケージ", "容器", "瓶", "びん": ("pack", "packs")
        default: ("serving", "servings")
        }
        self.init(singular: names.0, plural: names.1, ofBasis: ofBasis, perPack: perPack)
    }

    /// "1 piece", "3 pieces".
    func text(_ count: Int) -> String { "\(count) \(count == 1 ? singular : plural)" }
}

struct BasisSuggestion: Hashable, Codable, Sendable {
    var amount: Double
    var unit: PackUnit
    /// How it was worked out, e.g. "内容量 350 ml" or "内容量 120 g ÷ 6".
    var reason: String
}

import Foundation
import FoundationModels

/// What a backend reads off the screenshot: a transcription of the panel, nothing inferred.
/// The same shape is the NutriFacts API's response for the ai& option (see docs/aiand.md).
@Generable
nonisolated struct ExtractedLabel: Codable, Sendable, Hashable {
    @Guide(description: "True only if a Japanese nutrition facts panel (栄養成分表示) is visible.")
    var panelFound: Bool

    @Guide(description: "Product name if visible, in its original language, e.g. ポテトチップス うすしお味. Not the food type (名称). Empty if not visible.")
    var productName: String

    @Guide(description: "productName in plain English a shopper would know, keeping the brand, e.g. Potato Chips Lightly Salted. Empty if productName is empty.")
    var productNameEnglish: String

    @Guide(description: "Only the per-what phrase, without 栄養成分表示 or surrounding brackets, e.g. 1袋（60g）当たり, 100ml当たり or 1個当たり. Empty if not printed.")
    var basisText: String

    @Guide(description: "Weight or volume in the basis text, e.g. 60 for 1袋（60g）当たり, 100 for 100g当たり. 0 if the basis gives no amount (e.g. 1袋当たり).")
    var basisAmount: Double

    @Guide(description: "Unit of basisAmount: g or ml. Use ml for drinks labelled per ml.")
    var basisUnit: ExtractedUnit

    @Guide(description: "Net contents (内容量) weight or volume if printed anywhere in the image, e.g. 350 for 内容量 350ml or 120 for 120g（6個入り）. 0 if 内容量 is not visible or is only a count such as 2個.")
    var netContentsAmount: Double

    @Guide(description: "Unit of netContentsAmount: g, ml, or none when netContentsAmount is 0.")
    var netContentsUnit: ExtractedContentsUnit

    @Guide(description: "Number of pieces or servings the pack holds if 内容量 states it, e.g. 6 for 6個入り or 120g（6個）, 2 for 2本. 0 if not stated.")
    var netContentsCount: Int

    @Guide(description: "One entry per nutrient line that is actually printed. Never add lines that are not printed.")
    var lines: [ExtractedLine]

    @Guide(description: "True if the label says 推定値 or この表示値は、目安です or similar.")
    var isEstimate: Bool
}

@Generable
nonisolated enum ExtractedUnit: String, Codable, Sendable, Hashable { case g, ml }

@Generable
nonisolated enum ExtractedContentsUnit: String, Codable, Sendable, Hashable { case g, ml, none }

@Generable
nonisolated struct ExtractedLine: Codable, Sendable, Hashable {
    @Guide(description: "Which line this is. 糖質 is netCarbs, 糖類 is sugars, 食塩相当量 is salt, ナトリウム is sodium. Anything else is other.")
    var nutrient: ExtractedNutrient

    @Guide(description: "The line name exactly as printed, e.g. エネルギー or たんぱく質.")
    var printedName: String

    @Guide(description: "Lower value as printed. For a single value, the value itself. For 0, use 0.")
    var minValue: Double

    @Guide(description: "Upper value for ranges like 120〜150. Same as minValue for a single value.")
    var maxValue: Double

    @Guide(description: "Unit as printed: kcal, g, mg or µg.")
    var unit: String
}

@Generable
nonisolated enum ExtractedNutrient: String, Codable, Sendable, Hashable {
    case energy, protein, fat, saturatedFat, carbohydrate, netCarbs, sugars, fibre, salt, sodium, other
}

extension ExtractedLabel {
    /// Tolerates a Worker deployed before `productNameEnglish` was added.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        panelFound = try c.decode(Bool.self, forKey: .panelFound)
        productName = try c.decode(String.self, forKey: .productName)
        productNameEnglish = try c.decodeIfPresent(String.self, forKey: .productNameEnglish) ?? ""
        basisText = try c.decode(String.self, forKey: .basisText)
        basisAmount = try c.decode(Double.self, forKey: .basisAmount)
        basisUnit = try c.decode(ExtractedUnit.self, forKey: .basisUnit)
        netContentsAmount = try c.decode(Double.self, forKey: .netContentsAmount)
        netContentsUnit = try c.decode(ExtractedContentsUnit.self, forKey: .netContentsUnit)
        netContentsCount = try c.decode(Int.self, forKey: .netContentsCount)
        lines = try c.decode([ExtractedLine].self, forKey: .lines)
        isEstimate = try c.decode(Bool.self, forKey: .isEstimate)
    }

    enum MappingError: LocalizedError {
        case noPanel

        var errorDescription: String? {
            "No nutrition panel found. Small packs, alcohol, tea and spices may legally have none."
        }
    }

    /// Converts a transcription into the app's panel. Lines that weren't printed stay absent (rule 3).
    /// A basis without a size (1個当たり) keeps `basisAmount` nil; 内容量 only becomes a suggestion.
    func toPanel(photo: Data?) throws -> LabelPanel {
        guard panelFound, !lines.isEmpty else { throw MappingError.noPanel }
        // Models sometimes take the count in 1本当たり as 1 g. Only trust a size the basis actually prints.
        let basisAmount = Self.printsSize(basisText) ? basisAmount : 0

        var values: [NutrientKey: Double] = [:]
        var sodiumMg: Double?
        for line in lines {
            // A printed range (120〜150) is kept as its midpoint; LabelPanel holds one value per line.
            var value = (line.minValue + max(line.maxValue, line.minValue)) / 2
            let unit = line.unit.lowercased()
            switch line.nutrient {
            case .other:
                continue
            case .sodium:
                sodiumMg = unit == "g" ? value * 1000 : value // sodium switches to g at ≥ 1000 mg
                continue
            case .energy:
                if unit == "kj" { value /= 4.184 }
            default:
                if unit == "mg" { value /= 1000 }
            }
            guard let key = NutrientKey(rawValue: line.nutrient.rawValue), values[key] == nil else { continue }
            values[key] = value
        }
        // Only foods without added sodium salts may print sodium. Derive salt if it's missing.
        if values[.salt] == nil, let sodiumMg { values[.salt] = sodiumMg * 2.54 / 1000 }

        // 内容量 as a weight or volume, if it was in the photo. A bare count (2個) isn't a size.
        let contentsUnit: PackUnit? = switch netContentsUnit {
        case .g: .grams
        case .ml: .millilitres
        case .none: nil
        }
        let contents = netContentsAmount > 0 ? contentsUnit.map { (amount: netContentsAmount, unit: $0) } : nil
        let unit: PackUnit = basisAmount > 0 ? (basisUnit == .ml ? .millilitres : .grams) : (contents?.unit ?? (basisUnit == .ml ? .millilitres : .grams))
        let pack = contents?.unit == unit ? contents?.amount : nil
        let basis = Self.cleanBasis(basisText)

        var panel = LabelPanel(
            nickname: "",
            basisJapanese: basis.isEmpty ? (basisAmount > 0 ? "\(NumberFormat.amount(basisAmount, .protein))\(unit.rawValue)当たり" : "Basis not printed") : basis,
            basisAmount: nil,
            basisDescription: "per \(basis.isEmpty ? "serving" : basis.replacingOccurrences(of: "当たり", with: ""))",
            basisShort: basis.isEmpty ? "As labelled" : basis.replacingOccurrences(of: "当たり", with: ""),
            packAmount: pack,
            packShort: pack.map { "Pack · \(NumberFormat.amount($0, .protein)) \(unit.rawValue)" } ?? "Pack",
            unit: unit,
            printed: values.mapValues(Self.printed),
            isEstimate: isEstimate,
            ingredients: "",
            packColors: [0x8E8E93, 0x48484A],
            photo: photo)
        let name = productName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { panel.productName = TranslatedText(japanese: name, english: productNameEnglish.trimmingCharacters(in: .whitespaces)) }

        if basisAmount > 0 {
            let amount = NumberFormat.amount(basisAmount, .protein)
            panel.basisAmount = basisAmount
            panel.basisDescription = "per \(amount) \(unit.rawValue)"
            panel.basisShort = basisAmount == 100 ? "100 \(unit.rawValue)" : "Label · \(amount) \(unit.rawValue)"
        } else if let contents {
            // Never applied automatically: a pack can hold several pieces or servings.
            let count = max(netContentsCount, 1)
            let text = "内容量 \(NumberFormat.amount(contents.amount, .protein)) \(contents.unit.rawValue)"
            panel.basisSuggestion = BasisSuggestion(amount: contents.amount / Double(count), unit: contents.unit,
                                                    reason: count > 1 ? "\(text) ÷ \(count)" : text)
        }
        return panel
    }

    /// "栄養成分表示（1個当たり）" → "1個当たり". Brackets inside the phrase, as in 1食分（50g）当たり, stay.
    static func cleanBasis(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespaces)
        for prefix in ["栄養成分表示", "栄養成分"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        s = s.trimmingCharacters(in: .whitespaces)
        if let first = s.first, let last = s.last, "（(".contains(first), "）)".contains(last) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    /// True when the basis phrase has a weight or volume, like 1袋（60g）当たり or 100ml当たり. Empty counts as true.
    static func printsSize(_ text: String) -> Bool {
        text.isEmpty || text.range(of: #"[0-9０-９.．]+\s*(g|ｇ|ml|mL|ｍｌ|ミリリットル|グラム)"#, options: .regularExpression) != nil
    }

    /// As a label would print it: "0", "336", "21.6", "0.08".
    private static func printed(_ value: Double) -> String {
        if value == 0 { return "0" }
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

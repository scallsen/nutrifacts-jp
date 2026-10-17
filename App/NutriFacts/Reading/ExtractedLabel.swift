import Foundation
import FoundationModels

/// What a backend reads off the screenshot: a transcription of the panel, nothing inferred.
/// The same shape is the ai& backend's JSON response (see docs/backend-api.md).
@Generable
nonisolated struct ExtractedLabel: Codable, Sendable, Hashable {
    @Guide(description: "True only if a Japanese nutrition facts panel (栄養成分表示) is visible.")
    var panelFound: Bool

    @Guide(description: "Product name if visible, in its original language. Empty if not visible.")
    var productName: String

    @Guide(description: "The basis text exactly as printed after 栄養成分表示, e.g. 1袋（60g）当たり or 100ml当たり. Empty if not printed.")
    var basisText: String

    @Guide(description: "Weight or volume in the basis text, e.g. 60 for 1袋（60g）当たり, 100 for 100g当たり. 0 if the basis gives no amount (e.g. 1袋当たり).")
    var basisAmount: Double

    @Guide(description: "Unit of basisAmount: g or ml. Use ml for drinks labelled per ml.")
    var basisUnit: ExtractedUnit

    @Guide(description: "Net contents (内容量) amount if printed anywhere in the image, else 0.")
    var netContentsAmount: Double

    @Guide(description: "One entry per nutrient line that is actually printed. Never add lines that are not printed.")
    var lines: [ExtractedLine]

    @Guide(description: "True if the label says 推定値 or この表示値は、目安です or similar.")
    var isEstimate: Bool
}

@Generable
nonisolated enum ExtractedUnit: String, Codable, Sendable, Hashable { case g, ml }

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
    enum MappingError: LocalizedError {
        case noPanel
        /// The basis has no weight (e.g. 1袋当たり), so values can't be put per 100 g.
        case noBasisAmount(basis: String, netContents: Double?)

        var errorDescription: String? {
            switch self {
            case .noPanel:
                "No nutrition panel found. Small packs, alcohol, tea and spices may legally have none."
            case .noBasisAmount(let basis, let net):
                "The label is per “\(basis)” but doesn't say how much that is"
                    + (net.map { ", and 内容量 (\(NumberFormat.amount($0, .protein))) may cover several servings" } ?? "")
                    + ". Try a photo that includes the weight."
            }
        }
    }

    /// Converts a transcription into the app's panel. Lines that weren't printed stay absent (rule 3).
    func toPanel(photo: Data?) throws -> LabelPanel {
        guard panelFound, !lines.isEmpty else { throw MappingError.noPanel }
        // A basis without a weight isn't filled from 内容量: a bag can hold several servings or pieces.
        guard basisAmount > 0 else {
            throw MappingError.noBasisAmount(basis: basisText, netContents: netContentsAmount > 0 ? netContentsAmount : nil)
        }

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

        let unit: PackUnit = basisUnit == .ml ? .millilitres : .grams
        let amount = NumberFormat.amount(basisAmount, .protein)
        let pack = netContentsAmount > 0 ? netContentsAmount : basisAmount
        return LabelPanel(
            nickname: productName.isEmpty ? "Scanned label" : productName,
            basisJapanese: basisText.isEmpty ? "\(amount)\(unit.rawValue)当たり" : basisText,
            basisAmount: basisAmount,
            basisDescription: "per \(amount) \(unit.rawValue)",
            basisShort: basisAmount == 100 ? "100 \(unit.rawValue)" : "Label · \(amount) \(unit.rawValue)",
            packAmount: pack,
            packShort: "Pack · \(NumberFormat.amount(pack, .protein)) \(unit.rawValue)",
            unit: unit,
            printed: values.mapValues(Self.printed),
            isEstimate: isEstimate,
            ingredients: "",
            packColors: [0x8E8E93, 0x48484A],
            photo: photo)
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

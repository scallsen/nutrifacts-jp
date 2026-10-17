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
    enum MappingError: Error { case noPanel }

    /// Converts a transcription into the app's panel model. Lines that weren't printed stay absent (rule 3).
    func toPanel() throws -> NutritionPanel {
        guard panelFound, !lines.isEmpty else { throw MappingError.noPanel }
        var values: [Nutrient: Amount] = [:]
        var sodiumMg: Amount?

        for line in lines {
            var lo = line.minValue, hi = max(line.maxValue, line.minValue)
            let unit = line.unit.lowercased().replacingOccurrences(of: "μ", with: "µ")
            switch line.nutrient {
            case .other:
                continue
            case .sodium:
                // Sodium switches to g at ≥ 1000 mg.
                let toMg = unit == "g" ? 1000.0 : 1
                sodiumMg = Amount(min: lo * toMg, max: hi * toMg)
                continue
            case .energy:
                if unit == "kj" { lo /= 4.184; hi /= 4.184 }
            default:
                if unit == "mg" { lo /= 1000; hi /= 1000 }
            }
            guard let n = Nutrient(rawValue: line.nutrient.rawValue), values[n] == nil else { continue }
            var amount = Amount(min: lo, max: hi)
            amount.isPrintedZero = hi == 0
            values[n] = amount
        }
        // Only foods without added sodium salts may print sodium, alongside salt. Derive salt if it's missing.
        if values[.salt] == nil, let sodiumMg {
            var salt = Amount(min: sodiumMg.min * 2.54 / 1000, max: sodiumMg.max * 2.54 / 1000)
            salt.isPrintedZero = sodiumMg.max == 0
            values[.salt] = salt
        }

        // A basis without a weight (1袋当たり) isn't filled from 内容量 automatically: a bag can hold
        // several servings or pieces. The app offers 内容量 as a suggestion and the user confirms it.
        return NutritionPanel(
            productName: productName.isEmpty ? nil : productName,
            basis: Basis(label: basisText.isEmpty ? "Basis not printed" : basisText,
                         amount: basisAmount > 0 ? basisAmount : nil,
                         unit: BasisUnit(rawValue: basisUnit.rawValue)),
            values: values,
            isEstimate: isEstimate,
            netContents: netContentsAmount > 0 ? netContentsAmount : nil)
    }

}

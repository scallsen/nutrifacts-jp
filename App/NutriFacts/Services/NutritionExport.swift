import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Scans as text and CSV for other apps. The text is a plain list in the order nutrition labels outside
/// Japan use, with sodium in mg. A line the label doesn't print stays "not listed", never 0 (rule 3).
enum NutritionExport {
    /// The lines of the copied list, in order. Sodium is added after saturated fat.
    private static let trackerOrder: [(NutrientKey, String)] = [
        (.energy, "Calories"), (.fat, "Total fat"), (.saturatedFat, "Saturated fat"),
        (.carbohydrate, "Total carbohydrate"), (.fibre, "Dietary fiber"), (.sugars, "Sugars"), (.protein, "Protein"),
    ]

    /// One food, at the amount shown on the result, as a plain list.
    static func customFood(_ scan: Scan, analysis a: PanelAnalysis) -> String {
        var lines: [String] = []
        if let title = scan.title { lines.append(title) }
        if let printed = scan.printedTitle { lines.append(printed) }
        let amount = a.basisDescription.hasPrefix("per ") ? String(a.basisDescription.dropFirst(4)) : a.basisDescription
        lines.append("Serving size: \(amount)")
        for (key, name) in trackerOrder {
            lines.append("\(name): \(text(a.value(key), key))")
            if key == .saturatedFat {
                let sodium = a.sodiumMg.map { "\(Int($0.rounded())) mg (salt \(text(a.value(.salt), .salt)))" } ?? "not listed"
                lines.append("Sodium: \(sodium)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func text(_ value: ShownValue?, _ key: NutrientKey) -> String {
        guard let value else { return "not listed" }
        // A printed 0 is shown as 0, though it means "under the label's threshold".
        return "\(value.isUpperBound ? "0" : NumberFormat.amount(value.amount, key)) \(key.unit)"
    }

    // MARK: CSV

    private static let csvNutrients: [(NutrientKey, String)] = [
        (.energy, "Energy (kcal)"), (.protein, "Protein (g)"), (.fat, "Fat (g)"), (.saturatedFat, "Saturated fat (g)"),
        (.carbohydrate, "Carbohydrate (g)"), (.netCarbs, "Net carbs (g)"), (.sugars, "Sugars (g)"),
        (.fibre, "Fibre (g)"), (.salt, "Salt (g)"),
    ]

    /// Every scan, one row each, with values as printed for the label's basis. An empty cell is a line the
    /// label doesn't print.
    static func csv(_ scans: [Scan]) -> String {
        let header = ["Date", "Product", "Product (as printed)", "Food type", "Basis (as printed)", "Basis amount", "Unit",
                      "Pack amount"] + csvNutrients.map(\.1) + ["Sodium (mg)", "Estimated", "Allergens", "Ingredients"]
        let dateFormat = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash)
            .time(includingFractionalSeconds: false).timeSeparator(.colon)
        let rows = scans.map { scan -> [String] in
            let p = scan.panel
            let sodium = p.number(.salt).map { String(Int(($0 * 1000 / 2.54).rounded())) } ?? ""
            return [scan.date.formatted(dateFormat), scan.title ?? "", p.productName?.japanese ?? "",
                    scan.box?.category.english.nonEmpty ?? scan.box?.category.japanese ?? "", p.basisJapanese,
                    p.basisAmount.map { NumberFormat.amount($0, .protein) } ?? "", p.unit.rawValue,
                    p.packAmount.map { NumberFormat.amount($0, .protein) } ?? ""]
                + csvNutrients.map { p.printed[$0.0] ?? "" }
                + [sodium, p.isEstimate ? "yes" : "no",
                   scan.box.map { $0.allergens.map(ExtractedIngredientsBox.allergenName).joined(separator: ", ") } ?? "",
                   scan.box.map { $0.ingredients.map { $0.english.nonEmpty ?? $0.japanese }.joined(separator: ", ") } ?? ""]
        }
        return ([header] + rows).map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field when it holds a comma, quote or line break (RFC 4180).
    private static func field(_ value: String) -> String {
        guard value.contains(where: { ",\"\r\n".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// History as a CSV file for the share sheet.
struct HistoryCSV: Transferable {
    let scans: [Scan]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { csv in
            let url = FileManager.default.temporaryDirectory.appending(path: "NutriFacts History.csv")
            // A byte order mark so Excel reads the Japanese as UTF-8.
            try Data(("\u{FEFF}" + NutritionExport.csv(csv.scans)).utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

extension String {
    /// Nil for an empty string, for falling back with `??`.
    var nonEmpty: String? { isEmpty ? nil : self }
}

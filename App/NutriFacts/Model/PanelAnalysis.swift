import SwiftUI

enum Basis: String, CaseIterable, Identifiable, Sendable {
    case asLabelled, per100, wholePack
    var id: String { rawValue }
}

/// A value ready to show at the chosen basis.
struct ShownValue {
    var amount: Double
    var text: String
    /// The label printed "0", so this is an upper limit, not zero.
    var isUpperBound = false
    /// Worked out from other lines rather than printed.
    var isCalculated = false
}

/// High / low levels per 100 g/ml. Fat, saturated fat, sugars and salt use UK front-of-pack bands.
/// Fibre and protein use EU claim levels and are shown as positive.
enum Level {
    case low, medium, high, source, rich

    var word: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high, .rich: "High"
        case .source: "Source"
        }
    }

    var color: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        case .source, .rich: .teal
        }
    }
}

enum CarbState: String { case totalOnly = "A", sugarsOnly = "B", splitNoSugars = "C", full = "D" }

struct Percent {
    var text: String
    var value: Double
    var fromWHO: Bool
    /// The EU figure excludes fibre but only the total was available.
    var includesFibre: Bool
}

struct Notice: Identifiable {
    let id = UUID()
    var symbol: String
    var tint: Color
    var title: String
    var detail: String
}

/// Everything the result screen shows, worked out from one panel.
struct PanelAnalysis {
    let panel: LabelPanel
    let basis: Basis
    let source: ReferenceSource

    // MARK: Basis

    var availableBases: [Basis] {
        var bases: [Basis] = [.asLabelled]
        guard let amount = panel.basisAmount else { return bases }
        if amount != 100 { bases.append(.per100) }
        if let pack = panel.packAmount, pack != amount { bases.append(.wholePack) }
        return bases
    }

    func title(for basis: Basis) -> String {
        switch basis {
        case .asLabelled: panel.basisShort
        case .per100: "100 \(panel.unit.rawValue)"
        case .wholePack: panel.packShort
        }
    }

    /// Nil when the label's basis has no size, so values can only be shown as printed.
    var targetAmount: Double? {
        switch basis {
        case .asLabelled: panel.basisAmount
        case .per100: 100
        case .wholePack: panel.packAmount
        }
    }

    /// False for a basis like 1個当たり until its size is confirmed.
    var knowsBasisAmount: Bool { panel.basisAmount != nil }

    var basisDescription: String {
        switch basis {
        case .asLabelled: panel.basisDescription
        case .per100: "per 100 \(panel.unit.rawValue)"
        case .wholePack: "whole pack (\(NumberFormat.amount(panel.packAmount ?? 0, .protein)) \(panel.unit.rawValue))"
        }
    }

    // MARK: Values

    func printedValue(_ key: NutrientKey) -> ShownValue? {
        guard let raw = panel.printed[key], let number = Double(raw) else { return nil }
        if number == 0 {
            // "0" means under a threshold per 100 g/ml; without the basis size it can't be scaled.
            guard let target = targetAmount else { return ShownValue(amount: 0, text: "0 \(key.unit)", isUpperBound: true) }
            let limit = key.zeroThreshold * target / 100
            return ShownValue(amount: limit, text: "< \(NumberFormat.amount(limit, key)) \(key.unit)", isUpperBound: true)
        }
        if basis == .asLabelled { return ShownValue(amount: number, text: "\(raw) \(key.unit)") }
        guard let target = targetAmount, let basisAmount = panel.basisAmount else { return nil }
        let scaled = number * target / basisAmount
        return ShownValue(amount: scaled, text: "\(NumberFormat.amount(scaled, key)) \(key.unit)")
    }

    /// Printed values, plus net carbs and fibre worked out from the carb identity where possible.
    func value(_ key: NutrientKey) -> ShownValue? {
        if let printed = printedValue(key) { return printed }
        guard let carbs = printedValue(.carbohydrate) else { return nil }
        switch key {
        case .netCarbs:
            if let fibre = printedValue(.fibre) {
                let net = carbs.amount - fibre.amount
                return ShownValue(amount: net, text: "\(NumberFormat.amount(net, .netCarbs)) g", isCalculated: true)
            }
            if let sugars = printedValue(.sugars) {
                return ShownValue(amount: carbs.amount,
                                  text: "\(NumberFormat.amount(sugars.amount, .sugars))–\(NumberFormat.amount(carbs.amount, .carbohydrate)) g",
                                  isCalculated: true)
            }
            return nil
        case .fibre:
            guard let net = printedValue(.netCarbs) else { return nil }
            let fibre = carbs.amount - net.amount
            return ShownValue(amount: fibre, text: "\(NumberFormat.amount(fibre, .fibre)) g", isCalculated: true)
        default:
            return nil
        }
    }

    var sodiumMg: Double? {
        guard let salt = printedValue(.salt) else { return nil }
        return salt.amount * 1000 / 2.54
    }

    // MARK: Per 100 g bounds for missing lines

    /// The possible range per 100 g/ml for each line, using the label's own limits
    /// (sugars ≤ net carbs ≤ carbohydrate, saturated fat ≤ fat).
    /// Empty when the basis size isn't known.
    var bounds: [NutrientKey: ClosedRange<Double>] {
        guard let basisAmount = panel.basisAmount else { return [:] }
        func per100(_ key: NutrientKey) -> ClosedRange<Double>? {
            guard let number = panel.number(key) else { return nil }
            if number == 0 { return 0...key.zeroThreshold }
            let value = number * 100 / basisAmount
            return value...value
        }
        var result: [NutrientKey: ClosedRange<Double>] = [:]
        for key in NutrientKey.allCases { result[key] = per100(key) }
        let fat = result[.fat] ?? 0...0
        let carbs = result[.carbohydrate] ?? 0...0
        let printedFibre = result[.fibre], printedSugars = result[.sugars], printedNet = result[.netCarbs]
        if result[.saturatedFat] == nil { result[.saturatedFat] = 0...fat.upperBound }
        let net = printedNet ?? (printedFibre.map { max(0, carbs.lowerBound - $0.upperBound)...max(0, carbs.upperBound - $0.lowerBound) }
                                 ?? min(printedSugars?.lowerBound ?? 0, carbs.upperBound)...carbs.upperBound)
        result[.netCarbs] = net
        if printedSugars == nil { result[.sugars] = 0...net.upperBound }
        if printedFibre == nil {
            result[.fibre] = printedNet != nil
                ? max(0, carbs.lowerBound - net.upperBound)...max(0, carbs.upperBound - net.lowerBound)
                : 0...max(0, carbs.upperBound - (printedSugars?.lowerBound ?? 0))
        }
        return result
    }

    // MARK: Levels

    private static let foodBands: [NutrientKey: (Double, Double)] = [.fat: (3, 17.5), .saturatedFat: (1.5, 5), .sugars: (5, 22.5), .salt: (0.3, 1.5)]
    private static let drinkBands: [NutrientKey: (Double, Double)] = [.fat: (1.5, 8.75), .saturatedFat: (0.75, 2.5), .sugars: (2.5, 11.25), .salt: (0.3, 0.75)]

    private func band(_ value: Double, _ limits: (Double, Double)) -> Level {
        value <= limits.0 ? .low : value > limits.1 ? .high : .medium
    }

    /// The level, but only when every possible value falls in the same band.
    func level(_ key: NutrientKey) -> Level? {
        let b = bounds
        if let limits = (panel.unit.isDrink ? Self.drinkBands : Self.foodBands)[key] {
            guard panel.printed[key] != nil, let range = b[key] else { return nil }
            let low = band(range.lowerBound, limits), high = band(range.upperBound, limits)
            return low == high ? low : nil
        }
        switch key {
        case .fibre:
            guard value(.fibre) != nil, let range = b[.fibre] else { return nil }
            func claim(_ x: Double) -> Level? { x >= 6 ? .rich : x >= 3 ? .source : nil }
            let low = claim(range.lowerBound), high = claim(range.upperBound)
            return low == high ? low : nil
        case .protein:
            guard let protein = panel.number(.protein), let energy = panel.number(.energy), energy > 0 else { return nil }
            let share = protein * 4 / energy * 100
            return share >= 20 ? .rich : share >= 12 ? .source : nil
        default:
            return nil
        }
    }

    // MARK: Percent of daily value

    func percent(_ key: NutrientKey) -> Percent? {
        guard key != .netCarbs, let shown = value(key) else { return nil }
        guard let reference = source.reference(for: key) else { return nil }
        var amount = shown.amount
        var includesFibre = false
        // The EU's carbohydrate value excludes fibre, so compare net carbs when the label has them.
        if key == .carbohydrate, source.id == "eu" {
            if let net = value(.netCarbs), panel.printed[.netCarbs] != nil || panel.printed[.fibre] != nil {
                amount = net.amount
            } else {
                includesFibre = true
            }
        }
        let pct = shown.isUpperBound ? 0 : amount / reference.amount * 100
        return Percent(text: shown.isUpperBound ? "<1%" : NumberFormat.percent(pct) + (includesFibre ? "*" : ""),
                       value: pct, fromWHO: reference.fromWHO, includesFibre: includesFibre)
    }

    /// True when this source has a value (directly or from WHO) for the line.
    func hasReference(_ key: NutrientKey) -> Bool { key != .netCarbs && source.reference(for: key) != nil }

    // MARK: Carbohydrates

    var carbState: CarbState {
        let p = panel.printed
        if p[.netCarbs] == nil, p[.sugars] == nil, p[.fibre] == nil { return .totalOnly }
        if p[.sugars] != nil, p[.netCarbs] == nil, p[.fibre] == nil { return .sugarsOnly }
        if p[.sugars] == nil { return .splitNoSugars }
        return .full
    }

    // MARK: Things to know

    var energyAddsUp: Bool {
        let p = panel
        let protein = p.number(.protein) ?? 0, fat = p.number(.fat) ?? 0, carbs = p.number(.carbohydrate) ?? 0
        let calculated: Double
        if let net = p.number(.netCarbs) {
            calculated = protein * 4 + fat * 9 + net * 4 + (p.number(.fibre) ?? carbs - net) * 2
        } else {
            calculated = protein * 4 + fat * 9 + carbs * 4
        }
        guard let energy = p.number(.energy) else { return true }
        if energy == 0 {
            guard let basisAmount = p.basisAmount else { return true }
            return calculated < NutrientKey.energy.zeroThreshold * basisAmount / 100
        }
        return abs(calculated - energy) / energy <= 0.2
    }

    private static let watched: [(NutrientKey, String)] = [(.fat, "fat"), (.saturatedFat, "saturated fat"), (.sugars, "sugars"), (.salt, "salt")]

    var warnings: [Notice] {
        let b = bounds
        let bands = panel.unit.isDrink ? Self.drinkBands : Self.foodBands
        var notices: [Notice] = []
        var maybe: [String] = []
        for (key, word) in Self.watched {
            guard let range = b[key], let limits = bands[key] else { continue }
            if band(range.lowerBound, limits) == .high {
                notices.append(Notice(symbol: "exclamationmark.triangle.fill", tint: .red, title: "High in \(word)",
                                      detail: "\(NumberFormat.amount(range.lowerBound, key)) g per 100 \(panel.unit.rawValue)"))
            } else if band(range.upperBound, limits) == .high, panel.printed[key] == nil {
                maybe.append(word)
            }
        }
        if !maybe.isEmpty {
            notices.append(Notice(symbol: "questionmark", tint: .orange,
                                  title: "\(ListFormatter.localizedString(byJoining: maybe).capitalizedFirst) not listed",
                                  detail: "Could be high. The label doesn’t say."))
        }
        if panel.frontClaim == "糖質オフ" {
            notices.append(Notice(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "“糖質オフ” isn’t regulated",
                                  detail: "There’s no legal definition in Japan."))
        }
        if !energyAddsUp {
            notices.append(Notice(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Energy doesn’t add up",
                                  detail: "Check it against the label photo."))
        }
        return notices
    }

    var labelNotes: [Notice] {
        var notes: [Notice] = []
        if panel.frontClaim == "カロリーゼロ" {
            notes.append(Notice(symbol: "checkmark", tint: .green, title: "“カロリーゼロ” on the pack", detail: "Regulated: under 5 kcal per 100 ml."))
        }
        if panel.printed.values.contains("0") {
            notes.append(Notice(symbol: "0.circle", tint: .indigo, title: "“0” means very little",
                                detail: "Under a legal limit, e.g. fat under 0.5 g per 100 \(panel.unit.rawValue)."))
        }
        if panel.isEstimate {
            notes.append(Notice(symbol: "info", tint: .blue, title: "Estimated values", detail: "Marked 推定値: calculated, not lab tested."))
        }
        if energyAddsUp {
            notes.append(Notice(symbol: "checkmark", tint: .green, title: "Numbers add up", detail: "Energy matches protein, fat and carbs."))
        }
        return notes
    }

    // MARK: Footer

    func nutritionFooter(levelsShown: Bool) -> String {
        var parts = ["% of \(source.summary)."]
        let whoKeys = NutrientKey.allCases.filter { percent($0)?.fromWHO == true }
        if !whoKeys.isEmpty {
            let owner = source.id == "eu" ? "the EU has" : "\(source.name) has"
            parts.append("WHO rows use WHO limits where \(owner) no value" + (whoKeys.contains(.sugars) ? " (sugars may read high: WHO counts free sugars only)." : "."))
        }
        if percent(.carbohydrate)?.includesFibre == true { parts.append("*Includes fibre, so slightly high.") }
        if levelsShown { parts.append("Levels are per 100 \(panel.unit.rawValue).") }
        if NutrientKey.allCases.contains(where: { value($0) == nil }) { parts.append("Not listed means the label doesn’t say, not zero.") }
        return parts.joined(separator: " ")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

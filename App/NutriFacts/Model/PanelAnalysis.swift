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

/// How the chosen authority describes a line, in its own words: "Medium" (UK), "High" (FDA), "A lot" (Canada).
struct Verdict: Equatable {
    var text: String
    var color: Color
    var isHigh: Bool
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
    /// Shown when the info button next to the title is tapped.
    var info: String? = nil
}

/// Everything the result screen shows, worked out from one panel.
struct PanelAnalysis {
    let panel: LabelPanel
    let basis: Basis
    let source: ReferenceSource
    /// How many pieces, servings or packs (`portion`) the label's amount is shown for. Only used for
    /// `.asLabelled` on a label that isn't per 100 g/ml.
    var count = 1

    // MARK: Basis

    var availableBases: [Basis] { Self.availableBases(for: panel) }

    static func availableBases(for panel: LabelPanel) -> [Basis] {
        var bases: [Basis] = [.asLabelled]
        if let amount = panel.basisAmount, amount != 100 { bases.append(.per100) }
        if let pack = multiplier(.wholePack, count: 1, panel: panel), abs(pack - 1) > 0.001 { bases.append(.wholePack) }
        return bases
    }

    /// What the amount can be counted in: pieces, servings or packs. Nil for a label per 100 g/ml.
    var portion: Portion? { panel.portion }

    /// How many times the label's amount is shown, e.g. 3 for three pieces of a label per 1個. Nil when it
    /// can't be worked out: per 100 g for a basis whose weight isn't known.
    var multiplier: Double? { Self.multiplier(basis, count: count, panel: panel) }

    static func multiplier(_ basis: Basis, count: Int, panel: LabelPanel) -> Double? {
        switch basis {
        case .asLabelled:
            return panel.portion.map { Double(count) * $0.ofBasis } ?? 1
        case .per100:
            return panel.basisAmount.map { 100 / $0 }
        case .wholePack:
            // From the weights, or else from 内容量's count: a pack of 6個 is six labels per 1個.
            if let basisAmount = panel.basisAmount, let pack = panel.packAmount { return pack / basisAmount }
            guard let portion = panel.portion, let pieces = portion.perPack else { return nil }
            return Double(pieces) * portion.ofBasis
        }
    }

    func title(for basis: Basis) -> String {
        switch basis {
        case .asLabelled:
            return portion.map { $0.text(count) } ?? panel.basisShort
        case .per100:
            return "100 \(panel.unit.rawValue)"
        case .wholePack:
            if panel.packAmount == nil, let portion, let pieces = portion.perPack { return "Pack · \(portion.text(pieces))" }
            return panel.packShort
        }
    }

    /// The amount a result opens on: the whole pack when its size is known, as that's what's usually eaten
    /// or drunk. Otherwise the label's own basis.
    static func defaultBasis(for panel: LabelPanel) -> Basis {
        availableBases(for: panel).contains(.wholePack) ? .wholePack : .asLabelled
    }

    /// Says what the chosen amount is, under the size tabs. The label's serving is the maker's choice, not a standard one.
    var basisNote: String? {
        if basis == .asLabelled, let portion, count != 1 || portion.ofBasis != 1 || !knowsBasisAmount {
            return portionNote(portion)
        }
        return switch basis {
        case .wholePack:
            panel.packAmount == nil ? "The whole pack, from 内容量 (net contents). " + portionNote(portion) : "The whole pack, from 内容量 (net contents)."
        case .asLabelled where panel.basisAmount != nil && panel.basisAmount == panel.packAmount:
            "The label's amount is the whole pack."
        case .asLabelled where panel.basisAmount != 100:
            panel.packAmount == nil ? "The maker's serving size, which may not be the whole pack." : "The maker's serving size, not the whole pack."
        case .asLabelled, .per100:
            nil
        }
    }

    /// "The label is per 1包装, the whole pack." The basis stays in view however the amount is counted.
    private func portionNote(_ portion: Portion?) -> String {
        var note = "The label is per \(panel.basisUnitName)" + (panel.basisIsWholePack ? ", the whole pack." : ".")
        if let portion, let pieces = portion.perPack, pieces > 1 { note += " The pack holds \(portion.text(pieces))." }
        return note
    }

    /// The grams or ml shown. Nil when the label's basis has no size.
    var targetAmount: Double? {
        guard let basisAmount = panel.basisAmount, let multiplier else { return nil }
        return basisAmount * multiplier
    }

    /// False for a basis like 1個当たり until its size is confirmed.
    var knowsBasisAmount: Bool { panel.basisAmount != nil }

    var basisDescription: String {
        switch basis {
        case .asLabelled:
            guard let portion, count != 1 || portion.ofBasis != 1 else { return panel.basisDescription }
            return "per \(portion.text(count))" + (targetAmount.map { " (\(NumberFormat.amount($0, .protein)) \(panel.unit.rawValue))" } ?? "")
        case .wholePack where panel.packAmount == nil:
            return "whole pack (\(title(for: .wholePack).replacingOccurrences(of: "Pack · ", with: "")))"
        case .per100:
            return "per 100 \(panel.unit.rawValue)"
        case .wholePack:
            return "whole pack (\(NumberFormat.amount(panel.packAmount ?? 0, .protein)) \(panel.unit.rawValue))"
        }
    }

    // MARK: Values

    func printedValue(_ key: NutrientKey) -> ShownValue? {
        guard let raw = panel.printed[key], let number = Double(raw) else { return nil }
        if number == 0 {
            // "0" means under a threshold per 100 g/ml; without the basis size it can't be scaled.
            // Shown as printed, with the level "Low"; the amount is the upper limit for calculations.
            let limit = targetAmount.map { key.zeroThreshold * $0 / 100 } ?? 0
            return ShownValue(amount: limit, text: "0 \(key.unit)", isUpperBound: true)
        }
        guard let multiplier else { return nil }
        if multiplier == 1 { return ShownValue(amount: number, text: "\(raw) \(key.unit)") }
        let scaled = number * multiplier
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
        return limits(zero: { 0...$0.zeroThreshold }, scale: { $0 * 100 / basisAmount })
    }

    /// `bounds`, or for a basis whose weight isn't known (1個当たり), the same per one label amount. The FDA
    /// and Canada judge a serving, which that is, so they need no weight. A printed 0 is taken as 0 then,
    /// as its limit is per 100 g.
    private var ruleBounds: [NutrientKey: ClosedRange<Double>] {
        knowsBasisAmount ? bounds : limits(zero: { _ in 0...0 }, scale: { $0 })
    }

    /// The serving the rules judge, in the units of `ruleBounds`: `serving`, or 100 for a basis whose weight
    /// isn't known, as `ruleBounds` are then already per serving.
    private var ruleServing: Double? { knowsBasisAmount ? serving : panel.isPer100 ? nil : 100 }

    private func limits(zero: (NutrientKey) -> ClosedRange<Double>, scale: (Double) -> Double) -> [NutrientKey: ClosedRange<Double>] {
        func per100(_ key: NutrientKey) -> ClosedRange<Double>? {
            guard let number = panel.number(key) else { return nil }
            if number == 0 { return zero(key) }
            let value = scale(number)
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

    // MARK: The authority's words

    /// UK traffic-light limits per 100 g and per 100 ml: low at or below the first, high above the second.
    private static let foodBands: [NutrientKey: (Double, Double)] = [.fat: (3, 17.5), .saturatedFat: (1.5, 5), .sugars: (5, 22.5), .salt: (0.3, 1.5)]
    private static let drinkBands: [NutrientKey: (Double, Double)] = [.fat: (1.5, 8.75), .saturatedFat: (0.75, 2.5), .sugars: (2.5, 11.25), .salt: (0.3, 0.75)]

    private enum Band { case low, medium, high }

    private func band(_ value: Double, _ limits: (Double, Double)) -> Band {
        value <= limits.0 ? .low : value > limits.1 ? .high : .medium
    }

    /// Lines to eat less of: high is red and low is green. For the rest the words carry no colour,
    /// except a lot of fibre or protein, which is good.
    private static let limited: Set<NutrientKey> = [.fat, .saturatedFat, .sugars, .salt]

    private func color(_ key: NutrientKey, high: Bool) -> Color {
        if Self.limited.contains(key) { return high ? .red : .green }
        return high && (key == .fibre || key == .protein) ? .teal : .secondary
    }

    /// The size of one serving: the label's basis, unless the label is per 100 g/ml. Then a drink bottle
    /// under 720 ml is one serving, as the FDA counts a pack under twice the 360 ml reference amount.
    var serving: Double? {
        guard let amount = panel.basisAmount else { return nil }
        guard panel.isPer100 else { return amount }
        return servingIsPack ? panel.packAmount : nil
    }

    /// The serving is the whole bottle of a drink labelled per 100 ml.
    private var servingIsPack: Bool {
        guard panel.isPer100, panel.unit.isDrink, let pack = panel.packAmount, pack < 720 else { return false }
        return pack != panel.basisAmount
    }

    /// The % of the authority's own daily value in one serving (never a WHO stand-in, which its words
    /// aren't about).
    private func servingPercent(_ key: NutrientKey, per100: Double) -> Double? {
        guard key != .energy, let serving = ruleServing, let reference = source.values[key] else { return nil }
        return per100 * serving / 100 / reference * 100
    }

    /// The UK's portion rule: a portion over 100 g (150 ml) with more than 30% of the reference intake.
    private func ukPortionHigh(_ key: NutrientKey, per100: Double) -> Bool {
        guard let serving, AgencyRule.ukPortionApplies(serving: serving, isDrink: panel.unit.isDrink),
              let percent = servingPercent(key, per100: per100) else { return false }
        return percent > 30
    }

    /// How the chosen authority describes this line, in its own words, when every value the label
    /// allows gets the same words. Nil when it says nothing.
    func verdict(_ key: NutrientKey) -> Verdict? {
        guard let rule = source.rule, panel.printed[key] != nil, let range = ruleBounds[key] else { return nil }
        let words = bandVerdict(key, rule: rule, range: range)
        // A line Things to know warns about is high on its row too, e.g. Canada's "High in" symbol from 10%.
        if words?.isHigh != true, highReason(key, per100: range.lowerBound) != nil {
            return Verdict(text: rule == .healthCanada ? "High in" : rule.highWord, color: color(key, high: true), isHigh: true)
        }
        return words
    }

    /// A line the label leaves out that Things to know says may be high.
    func mayBeHigh(_ key: NutrientKey) -> Bool {
        guard panel.printed[key] == nil, let range = ruleBounds[key] else { return false }
        return highReason(key, per100: range.lowerBound) == nil && highReason(key, per100: range.upperBound) != nil
    }

    private func bandVerdict(_ key: NutrientKey, rule: AgencyRule, range: ClosedRange<Double>) -> Verdict? {
        if let bands = rule.percentBands {
            guard let low = servingPercent(key, per100: range.lowerBound),
                  let high = servingPercent(key, per100: range.upperBound) else { return nil }
            if low >= bands.high { return Verdict(text: rule.highWord, color: color(key, high: true), isHigh: true) }
            if high <= bands.low { return Verdict(text: rule.lowWord, color: color(key, high: false), isHigh: false) }
            return nil
        }
        // The UK's lights are per 100 g/ml, so they need the weight.
        guard knowsBasisAmount, let limits = (panel.unit.isDrink ? Self.drinkBands : Self.foodBands)[key] else { return nil }
        if ukPortionHigh(key, per100: range.lowerBound) || band(range.lowerBound, limits) == .high {
            return Verdict(text: "High", color: .red, isHigh: true)
        }
        switch (band(range.lowerBound, limits), band(range.upperBound, limits)) {
        case (.low, .low): return Verdict(text: "Low", color: .green, isHigh: false)
        case (.medium, .medium): return Verdict(text: "Medium", color: .orange, isHigh: false)
        default: return nil
        }
    }

    /// Why a line is high, in the authority's terms, when it is. For Canada that's the "High in" symbol.
    /// With `upTo`, the amount is the most the label allows, and the reason says so.
    private func highReason(_ key: NutrientKey, per100: Double, upTo: Bool = false) -> String? {
        guard let rule = source.rule else { return nil }
        let unit = panel.unit.rawValue
        let upToText = upTo ? "Up to " : ""
        let inServing = { (percent: Double) -> String in
            guard self.knowsBasisAmount else {
                return "\(upToText)\(NumberFormat.percent(percent)) of the daily value in \(self.servingWords)."
            }
            return "\(upToText)\(NumberFormat.percent(percent)) of the daily value in \(self.servingIsPack ? "the" : "one") \(NumberFormat.amount(self.serving ?? 0, .protein)) \(unit) \(self.servingIsPack ? "bottle" : "serving")."
        }
        switch rule {
        case .uk:
            guard knowsBasisAmount, let limits = (panel.unit.isDrink ? Self.drinkBands : Self.foodBands)[key] else { return nil }
            if band(per100, limits) == .high {
                return "\(upToText)\(NumberFormat.amount(per100, key)) g per 100 \(unit). The UK calls over \(NumberFormat.amount(limits.1, key)) g high."
            }
            guard ukPortionHigh(key, per100: per100), let percent = servingPercent(key, per100: per100) else { return nil }
            return "\(inServing(percent)) The UK calls a portion over \(panel.unit.isDrink ? "150 ml" : "100 g") high above 30%."
        case .fda:
            guard Self.limited.contains(key), let percent = servingPercent(key, per100: per100), percent >= 20 else { return nil }
            return "\(inServing(percent)) The FDA calls 20% or more high."
        case .healthCanada:
            guard key != .fat, Self.limited.contains(key), let serving, let percent = servingPercent(key, per100: per100) else {
                // Without the weight, the threshold for most foods: 15%, or 10% for 30 g or less.
                guard !knowsBasisAmount, key != .fat, Self.limited.contains(key), let percent = servingPercent(key, per100: per100),
                      percent >= 15 else { return nil }
                return "\(inServing(percent)) Canada requires a “High in” symbol from 15% for most foods."
            }
            let threshold = AgencyRule.canadaHighInAt(serving: serving, isDrink: panel.unit.isDrink)
            guard percent >= threshold else { return nil }
            return "\(inServing(percent)) Canada requires a “High in” symbol from \(Int(threshold))%."
        }
    }

    /// One label amount, for a basis whose weight isn't known: "one piece", or "the pack" for a label per pack.
    private var servingWords: String {
        if let portion, portion.ofBasis == 1 { return "one \(portion.singular)" }
        return panel.basisIsWholePack ? "the pack" : "one \(panel.basisUnitName)"
    }

    // MARK: Percent of daily value

    func percent(_ key: NutrientKey) -> Percent? {
        guard key != .netCarbs, let shown = value(key) else { return nil }
        guard let reference = source.reference(for: key) else { return nil }
        var amount = shown.amount
        var includesFibre = false
        // The EU's and UK's carbohydrate value excludes fibre, so compare net carbs when the label has them.
        if key == .carbohydrate, source.carbohydrateExcludesFibre {
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

    /// High levels, then notes on the label itself.
    var warnings: [Notice] {
        var notices = levelWarnings
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

    private var levelWarnings: [Notice] {
        guard source.rule != nil else { return [] }
        let b = ruleBounds
        var notices: [Notice] = []
        for (key, word) in Self.watched {
            guard let range = b[key] else { continue }
            if let reason = highReason(key, per100: range.lowerBound) {
                notices.append(Notice(symbol: "exclamationmark.triangle.fill", tint: .red, title: "High in \(word)", detail: reason))
            } else if panel.printed[key] == nil, let reason = highReason(key, per100: range.upperBound, upTo: true) {
                // Not on the label, but the line above it leaves room for a high amount.
                let parent = key == .saturatedFat ? "fat" : "carbohydrate"
                notices.append(Notice(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "May be high in \(word)", detail: reason,
                                      info: "A \(parent) breakdown is not provided by the label, so this is an estimate."))
            }
        }
        return notices
    }

    /// Why the authority's words can't apply, or that nothing is high. Nil when something is.
    var guidanceNotice: Notice? {
        guard let rule = source.rule else { return nil }
        if rule == .uk, !knowsBasisAmount {
            return Notice(symbol: "scalemass", tint: .gray, title: "Traffic lights need the weight",
                          detail: "The UK’s are per 100 \(panel.unit.rawValue), and the label doesn’t say what \(panel.basisUnitName) weighs. Add it below.")
        }
        if rule.percentBands != nil, ruleServing == nil {
            let who = rule == .fda ? "The FDA" : "Health Canada"
            return Notice(symbol: "info", tint: .gray, title: "No serving size",
                          detail: "\(who) judges amounts per serving, and this label is per 100 \(panel.unit.rawValue).")
        }
        let detail = switch rule {
        case .uk: "No red traffic lights for fat, saturated fat, sugars or salt."
        case .fda: "Nothing is 20% or more of the daily value per serving."
        case .healthCanada: "It wouldn’t need a “High in” symbol."
        }
        return levelWarnings.isEmpty ? Notice(symbol: "checkmark", tint: .green, title: "Nothing high", detail: detail) : nil
    }

    var labelNotes: [Notice] {
        var notes: [Notice] = []
        if panel.frontClaim == "カロリーゼロ" {
            notes.append(Notice(symbol: "checkmark", tint: .green, title: "“カロリーゼロ” on the pack", detail: "Regulated: under 5 kcal per 100 ml."))
        }
        if energyAddsUp {
            notes.append(Notice(symbol: "checkmark", tint: .green, title: "Numbers add up", detail: "Energy matches protein, fat and carbs."))
        }
        return notes
    }

    // MARK: Footer

    var nutritionFooter: String {
        var parts = ["% of \(source.summary)."]
        let whoKeys = NutrientKey.allCases.filter { percent($0)?.fromWHO == true }
        if !whoKeys.isEmpty {
            let owner = source.id == "eu" ? "the EU has" : source.id == "uk" ? "the UK has" : "\(source.name) has"
            parts.append("WHO rows use WHO limits where \(owner) no value" + (whoKeys.contains(.sugars) ? " (sugars may read high: WHO counts free sugars only)." : "."))
        }
        if percent(.carbohydrate)?.includesFibre == true { parts.append("*Includes fibre, so slightly high.") }
        if let rule = source.rule {
            let words = switch rule {
            case .uk: "Low, Medium and High are the UK’s traffic lights per 100 \(panel.unit.rawValue), and High for a portion over \(panel.unit.isDrink ? "150 ml" : "100 g") with over 30%."
            case .fda: "Low and High are the FDA’s: 5% or less and 20% or more per serving."
            case .healthCanada: "A little and A lot are Health Canada’s: 5% or less and 15% or more per serving."
            }
            parts.append(words)
        }
        if NutrientKey.allCases.contains(where: { value($0) == nil }) { parts.append("Not listed means the label doesn’t say, not zero.") }
        return parts.joined(separator: " ")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

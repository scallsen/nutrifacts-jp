import Foundation

/// Consistency checks from docs/ui-domain-context.md §7. A failure usually means a misread.
nonisolated struct SanityIssue: Hashable, Codable, Sendable {
    var message: String
}

nonisolated enum SanityChecks {
    static func run(_ panel: NutritionPanel) -> [SanityIssue] {
        var issues: [SanityIssue] = []
        let v = { (n: Nutrient) in panel[n]?.midpoint }

        if let c = v(.carbohydrate), let net = v(.netCarbs), let fib = v(.fibre), abs(net + fib - c) > 1.05 {
            issues.append(.init(message: "Net carbs + fibre (\(fmt(net + fib)) g) doesn't match carbohydrate (\(fmt(c)) g)."))
        }
        if let s = v(.sugars), let upper = v(.netCarbs) ?? v(.carbohydrate), s > upper + 0.05 {
            issues.append(.init(message: "Sugars (\(fmt(s)) g) are more than \(panel[.netCarbs] != nil ? "net carbs" : "carbohydrate") (\(fmt(upper)) g)."))
        }
        if let net = v(.netCarbs), let c = v(.carbohydrate), net > c + 0.05 {
            issues.append(.init(message: "Net carbs (\(fmt(net)) g) are more than carbohydrate (\(fmt(c)) g)."))
        }
        if let sat = v(.saturatedFat), let fat = v(.fat), sat > fat + 0.05 {
            issues.append(.init(message: "Saturated fat (\(fmt(sat)) g) is more than fat (\(fmt(fat)) g)."))
        }
        if let kcal = v(.energy), kcal >= 20, let p = v(.protein), let f = v(.fat) {
            let carbKcal: Double
            if let net = v(.netCarbs), let fib = v(.fibre) {
                carbKcal = net * 4 + fib * 2
            } else if let c = v(.carbohydrate) {
                carbKcal = c * 4
            } else {
                carbKcal = .nan
            }
            let estimate = p * 4 + f * 9 + carbKcal
            if estimate.isFinite, estimate > 0, abs(kcal - estimate) / estimate > 0.2 {
                // Sugar alcohols lower kcal; that's not an error when 糖質 ≫ 糖類.
                let likelyPolyols = kcal < estimate && (v(.netCarbs) ?? 0) > (v(.sugars) ?? .infinity) * 2
                if !likelyPolyols {
                    issues.append(.init(message: "Energy (\(fmt(kcal)) kcal) is more than 20% off the \(fmt(estimate)) kcal the macros add up to."))
                }
            }
        }
        if let per100 = panel.per100(), let salt = per100[.salt], salt.max > 30 {
            issues.append(.init(message: "Salt over 30 g per 100 g. A decimal point may have been lost."))
        }
        return issues
    }

    private static func fmt(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(0...1))) }
}

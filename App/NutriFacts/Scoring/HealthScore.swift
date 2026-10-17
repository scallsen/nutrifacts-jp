import Foundation

/// Decodes `data/health-score.json`. See docs/health-score.md.
nonisolated struct ScoreRubric: Decodable, Sendable {
    struct Band: Decodable, Sendable { var low: Double; var high: Double }
    struct PositiveBand: Decodable, Sendable { var source: Double; var high: Double }
    struct Negative: Decodable, Sendable { var weight: Double; var solid: Band; var drink: Band }
    struct Positive: Decodable, Sendable { var weight: Double; var solid: PositiveBand; var drink: PositiveBand }
    struct Grade: Decodable, Sendable { var grade: String; var min: Double }

    var displayName: String
    var start: Double
    var negatives: [String: Negative]
    var positives: [String: Positive]
    var grades: [Grade]

    static let shared: ScoreRubric = {
        guard let url = Bundle.main.url(forResource: "health-score", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ScoreRubric.self, from: data)
        else { fatalError("health-score.json is missing from the app bundle") }
        return decoded
    }()

    func grade(for score: Double) -> String {
        grades.sorted { $0.min > $1.min }.first { score >= $0.min }?.grade ?? "E"
    }
}

/// A grade for one panel. When lines aren't disclosed it's a range from the worst to the best case.
struct HealthScore: Hashable, Sendable {
    struct Component: Hashable, Sendable, Identifiable {
        enum Status: Hashable, Sendable { case stated, notDisclosed, printedZero }
        var key: NutrientKey
        /// Per-100 g/ml value used, as a range.
        var value: ClosedRange<Double>
        /// Points, negative for penalties. A range when the value is a range.
        var points: ClosedRange<Double>
        var status: Status
        var id: NutrientKey { key }
    }

    var score: ClosedRange<Double>
    var worstGrade: String
    var bestGrade: String
    var components: [Component]
    var rubricName: String

    var isExact: Bool { score.upperBound - score.lowerBound < 0.5 }
    var gradeText: String { worstGrade == bestGrade ? bestGrade : "\(bestGrade)–\(worstGrade)" }
    var scoreText: String {
        let lo = Int(score.lowerBound.rounded()), hi = Int(score.upperBound.rounded())
        return lo == hi ? "\(hi)" : "\(lo)–\(hi)"
    }
    /// Lines whose absence widens the range.
    var widenedBy: [NutrientKey] {
        components.filter { $0.status == .notDisclosed && $0.points.lowerBound < $0.points.upperBound }.map(\.key)
    }
}

extension PanelAnalysis {
    /// The health score, per 100 g/ml. Uses `bounds`, so a missing line is scored across every
    /// value the label allows (sugars ≤ net carbs ≤ carbohydrate, saturated fat ≤ fat), never as 0.
    /// Nil while the basis size is unknown (1個当たり), because nothing can be put per 100 g.
    func healthScore(rubric: ScoreRubric = .shared) -> HealthScore? {
        guard knowsBasisAmount else { return nil }
        let drink = panel.unit.isDrink
        let b = bounds
        var components: [HealthScore.Component] = []

        func status(_ key: NutrientKey) -> HealthScore.Component.Status {
            guard let printed = panel.number(key) else { return .notDisclosed }
            return printed == 0 ? .printedZero : .stated
        }

        for (name, rule) in rubric.negatives {
            guard let key = NutrientKey(rawValue: name), let range = b[key] else { continue }
            let band = drink ? rule.drink : rule.solid
            let points = { (x: Double) in -rule.weight * Self.clamp((x - band.low) / (band.high - band.low)) }
            components.append(.init(key: key, value: range, points: points(range.upperBound)...points(range.lowerBound), status: status(key)))
        }

        // Positives earn points only when printed: an undisclosed fibre line gets no credit.
        for (name, rule) in rubric.positives {
            guard let key = NutrientKey(rawValue: name) else { continue }
            guard panel.printed[key] != nil, let range = b[key] else {
                components.append(.init(key: key, value: 0...0, points: 0...0, status: .notDisclosed))
                continue
            }
            let band = drink ? rule.drink : rule.solid
            let points = { (x: Double) -> Double in
                x < band.source ? 0 : rule.weight * (0.5 + 0.5 * Self.clamp((x - band.source) / (band.high - band.source)))
            }
            components.append(.init(key: key, value: range, points: points(range.lowerBound)...points(range.upperBound), status: status(key)))
        }

        let order = NutrientKey.allCases
        components.sort { order.firstIndex(of: $0.key)! < order.firstIndex(of: $1.key)! }
        let worst = Self.clamp(rubric.start + components.map(\.points.lowerBound).reduce(0, +), 0, 100)
        let best = Self.clamp(rubric.start + components.map(\.points.upperBound).reduce(0, +), 0, 100)
        return HealthScore(score: worst...best, worstGrade: rubric.grade(for: worst), bestGrade: rubric.grade(for: best),
                           components: components, rubricName: rubric.displayName)
    }

    private static func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(max(x, lo), hi) }
}

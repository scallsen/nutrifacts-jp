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

nonisolated struct HealthScore: Hashable, Sendable {
    struct Component: Hashable, Sendable, Identifiable {
        enum Status: Hashable, Sendable { case stated, notDisclosed, printedZero }
        var nutrient: Nutrient
        /// Per-100 value used, as a range.
        var value: ClosedRange<Double>
        /// Points, negative for penalties. A range when the value is a range.
        var points: ClosedRange<Double>
        var status: Status
        var id: Nutrient { nutrient }
    }

    /// Worst … best case.
    var score: ClosedRange<Double>
    var worstGrade: String
    var bestGrade: String
    var components: [Component]
    var isDrink: Bool
    var rubricName: String

    var isExact: Bool { score.upperBound - score.lowerBound < 0.5 }
    var gradeText: String { worstGrade == bestGrade ? bestGrade : "\(bestGrade)–\(worstGrade)" }
    var scoreText: String {
        let lo = Int(score.lowerBound.rounded()), hi = Int(score.upperBound.rounded())
        return lo == hi ? "\(hi)" : "\(lo)–\(hi)"
    }
    var undisclosed: [Nutrient] { components.filter { $0.status == .notDisclosed }.map(\.nutrient) }
}

nonisolated enum HealthScorer {
    enum Failure: Error, Equatable {
        /// The basis has no weight (e.g. 1袋当たり with no 内容量), so per-100 values can't be computed.
        case needsBasisAmount
    }

    static func score(_ panel: NutritionPanel, rubric: ScoreRubric = .shared) -> Result<HealthScore, Failure> {
        guard let per100 = panel.per100() else { return .failure(.needsBasisAmount) }
        let drink = panel.basis.isDrink
        var components: [HealthScore.Component] = []

        // Negatives: missing lines are bounded by their parent line (docs/health-score.md).
        for (key, rule) in rubric.negatives {
            guard let n = Nutrient(rawValue: key) else { continue }
            let band = drink ? rule.drink : rule.solid
            let (range, status) = negativeRange(n, per100)
            guard let range else { continue }
            let p = { (x: Double) in -rule.weight * clamp((x - band.low) / (band.high - band.low)) }
            components.append(.init(nutrient: n, value: range, points: p(range.upperBound)...p(range.lowerBound), status: status))
        }

        // Positives: only stated values earn a bonus.
        for (key, rule) in rubric.positives {
            guard let n = Nutrient(rawValue: key) else { continue }
            let band = drink ? rule.drink : rule.solid
            guard let a = per100[n] else {
                components.append(.init(nutrient: n, value: 0...0, points: 0...0, status: .notDisclosed))
                continue
            }
            let b = { (x: Double) -> Double in
                x < band.source ? 0 : rule.weight * (0.5 + 0.5 * clamp((x - band.source) / (band.high - band.source)))
            }
            components.append(.init(nutrient: n, value: a.min...a.max, points: b(a.min)...b(a.max),
                                    status: a.isPrintedZero ? .printedZero : .stated))
        }

        let order = Nutrient.allCases
        components.sort { order.firstIndex(of: $0.nutrient)! < order.firstIndex(of: $1.nutrient)! }

        let worst = clamp(rubric.start + components.map(\.points.lowerBound).reduce(0, +), 0, 100)
        let best = clamp(rubric.start + components.map(\.points.upperBound).reduce(0, +), 0, 100)
        return .success(HealthScore(score: worst...best,
                                    worstGrade: rubric.grade(for: worst), bestGrade: rubric.grade(for: best),
                                    components: components, isDrink: drink, rubricName: rubric.displayName))
    }

    private static func negativeRange(_ n: Nutrient, _ v: [Nutrient: Amount]) -> (ClosedRange<Double>?, HealthScore.Component.Status) {
        if let a = v[n] { return (a.min...a.max, a.isPrintedZero ? .printedZero : .stated) }
        let parent: Amount?
        switch n {
        case .saturatedFat: parent = v[.fat]
        case .sugars: parent = v[.netCarbs] ?? v[.carbohydrate] // 糖類 ⊂ 糖質 ⊂ 炭水化物
        default: parent = nil
        }
        guard let parent else { return (nil, .notDisclosed) }
        return (0...parent.max, .notDisclosed)
    }

    private static func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(max(x, lo), hi) }
}

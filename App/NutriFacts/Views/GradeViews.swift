import SwiftUI

extension Color {
    static func grade(_ letter: String) -> Color {
        switch letter {
        case "A": Color(hex: 0x218C4D)
        case "B": Color(hex: 0x73AD33)
        case "C": Color(hex: 0xEDB81A)
        case "D": Color(hex: 0xEB7D21)
        default: Color(hex: 0xD6382E)
        }
    }
}

/// The grade, or the span of grades the label allows when lines aren't disclosed.
struct GradeBadge: View {
    var score: HealthScore
    var size: CGFloat = 64

    var body: some View {
        HStack(spacing: size * 0.08) {
            letter(score.bestGrade)
            if score.bestGrade != score.worstGrade {
                Text("–").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.secondary)
                letter(score.worstGrade)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.bestGrade == score.worstGrade ? "Grade \(score.bestGrade)" : "Grade \(score.bestGrade) to \(score.worstGrade)")
    }

    private func letter(_ g: String) -> some View {
        Text(g)
            .font(.system(size: size * 0.62, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.grade(g), in: .rect(cornerRadius: size * 0.22))
    }
}

/// 0–100 track with the possible score range highlighted.
struct ScoreRangeBar: View {
    var score: HealthScore

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let lo = score.score.lowerBound / 100 * w, hi = score.score.upperBound / 100 * w
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(colors: [.grade(score.worstGrade), .grade(score.bestGrade)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(hi - lo, 8))
                    .offset(x: min(lo, w - 8))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Top of the result: grade, score and why it's a range.
struct HealthScoreSection: View {
    let analysis: PanelAnalysis

    var body: some View {
        let score = analysis.healthScore()
        Section {
            HStack(spacing: 16) {
                GradeBadge(score: score, size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(score.scoreText) / 100").font(.title3.weight(.semibold)).monospacedDigit()
                    ScoreRangeBar(score: score)
                }
            }
            .padding(.vertical, 4)
            NavigationLink("How it's scored") { ScoreBreakdownView(analysis: analysis, score: score) }
        } header: {
            Text("Health score")
        } footer: {
            Text(footer(score))
        }
    }

    private func footer(_ score: HealthScore) -> String {
        let per = "Per 100 \(analysis.panel.unit.rawValue)."
        guard !score.widenedBy.isEmpty else { return per }
        let names = ListFormatter.localizedString(byJoining: score.widenedBy.map { $0.english.lowercased() })
        return "A range, because the label doesn't list \(names). \(per)"
    }
}

struct ScoreBreakdownView: View {
    let analysis: PanelAnalysis
    let score: HealthScore

    var body: some View {
        let unit = analysis.panel.unit.rawValue
        List {
            Section {
                ForEach(score.components) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.key.english)
                            Text(detail(c, unit: unit)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(points(c.points)).monospacedDigit()
                            .foregroundStyle(c.points.upperBound > 0 ? .teal : (c.points.lowerBound < -0.5 ? .red : .secondary))
                    }
                }
            } header: {
                Text("Starts at 100")
            } footer: {
                Text("\(score.rubricName). Fat, saturated fat, sugars and salt lose points between Japan's “low” claim level and the UK's “high” level. Protein and fibre gain points from Japan's “source of” level. Lines the label doesn't list are scored at every value they could have, so the grade becomes a range. A = 80+, B = 65+, C = 50+, D = 35+.")
            }
        }
        .navigationTitle("How It's Scored")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ c: HealthScore.Component, unit: String) -> String {
        let fmt = { NumberFormat.amount($0, c.key) }
        switch c.status {
        case .notDisclosed where c.value.upperBound == 0: return "Not listed, so no points"
        case .notDisclosed: return "Not listed · could be 0–\(fmt(c.value.upperBound)) g per 100 \(unit)"
        case .printedZero: return "Printed as 0 · under \(fmt(c.value.upperBound)) g per 100 \(unit)"
        case .stated: return "\(fmt(c.value.lowerBound)) g per 100 \(unit)"
        }
    }

    private func points(_ p: ClosedRange<Double>) -> String {
        let f = { (x: Double) in x.rounded() == 0 ? "0" : (x > 0 ? "+" : "−") + "\(Int(abs(x).rounded()))" }
        return Int(p.lowerBound.rounded()) == Int(p.upperBound.rounded()) ? f(p.lowerBound) : "\(f(p.upperBound)) to \(f(p.lowerBound))"
    }
}

/// Compact result for the Shortcuts / Action Button snippet.
struct ScoreSnippetView: View {
    var panel: LabelPanel?
    var message: String

    var body: some View {
        if let panel {
            let a = PanelAnalysis(panel: panel, basis: .per100, source: .with(id: UserDefaults.standard.string(forKey: "referenceSource") ?? "jp"))
            let score = a.healthScore()
            HStack(spacing: 14) {
                GradeBadge(score: score, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(panel.nickname).font(.headline).lineLimit(1)
                    Text("\(score.scoreText) / 100 · per 100 \(panel.unit.rawValue)").font(.subheadline).foregroundStyle(.secondary)
                    if let first = a.warnings.first {
                        Text(first.title).font(.caption).foregroundStyle(first.tint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
        } else {
            Text(message).padding()
        }
    }
}

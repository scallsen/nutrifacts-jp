import SwiftUI

extension Color {
    static func grade(_ letter: String) -> Color {
        switch letter {
        case "A": Color(red: 0.13, green: 0.55, blue: 0.30)
        case "B": Color(red: 0.45, green: 0.68, blue: 0.20)
        case "C": Color(red: 0.93, green: 0.72, blue: 0.10)
        case "D": Color(red: 0.92, green: 0.49, blue: 0.13)
        default: Color(red: 0.84, green: 0.22, blue: 0.18)
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

/// Compact result for the Shortcuts / Action Button snippet.
struct ScoreSnippetView: View {
    var outcome: ScanOutcome
    var backend: Backend

    var body: some View {
        switch outcome {
        case .scored(let panel, let score, let issues):
            HStack(alignment: .center, spacing: 14) {
                GradeBadge(score: score, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(panel.productName ?? "Nutrition label").font(.headline).lineLimit(1)
                    Text("\(score.scoreText) / 100 · \(panel.basis.per100Label)").font(.subheadline).foregroundStyle(.secondary)
                    if !score.undisclosed.isEmpty {
                        Text("Not disclosed: \(score.undisclosed.map(\.english).joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if !issues.isEmpty {
                        Label("Check the reading in the app", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
        default:
            Text(outcome.summary).padding()
        }
    }
}

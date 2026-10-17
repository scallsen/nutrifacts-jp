import SwiftUI

/// The scored, simplified view of one label.
struct ResultView: View {
    var title: String
    var outcome: ScanOutcome
    var backend: Backend?
    /// Present for saved scans, so the user can supply a missing basis weight.
    var scan: Scan?

    @AppStorage("dvSource") private var dvSource = DailyValues.shared.defaultSource

    var body: some View {
        List {
            switch outcome {
            case .failed(let message):
                ContentUnavailableView("Couldn't read the label", systemImage: "exclamationmark.triangle", description: Text(message))
            case .noPanel:
                ContentUnavailableView("No nutrition panel", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Small packs, alcohol, tea and spices may legally have no panel."))
            case .needsBasisAmount(let panel):
                BasisAmountSection(panel: panel, scan: scan)
                LabelSection(panel: panel, dvSource: dvSource)
            case .scored(let panel, let score, let issues):
                ScoreHeader(panel: panel, score: score)
                if !issues.isEmpty {
                    Section("Check the reading") {
                        ForEach(issues, id: \.self) { Label($0.message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }
                }
                BreakdownSection(score: score, panel: panel)
                CarbSection(panel: panel)
                LabelSection(panel: panel, dvSource: dvSource)
            }
            Section {
                if let backend { LabeledContent("Read by", value: backend.title) }
                LabeledContent("Score", value: ScoreRubric.shared.displayName)
                LabeledContent("Daily values", value: DailyValues.shared.sources[dvSource]?.version.displayName ?? dvSource)
            } footer: {
                Text("Labels may legally differ from reality by ±20%. Small differences between products aren't meaningful.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ScoreHeader: View {
    var panel: NutritionPanel
    var score: HealthScore

    var body: some View {
        Section {
            VStack(spacing: 12) {
                GradeBadge(score: score, size: 72)
                Text("\(score.scoreText) / 100").font(.title2.weight(.semibold)).monospacedDigit()
                ScoreRangeBar(score: score)
                if !score.isExact {
                    Text(rangeExplanation).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                HStack(spacing: 8) {
                    Text("Scored \(panel.basis.per100Label)")
                    if panel.isEstimate { Text("·"); Text("Estimated values") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var rangeExplanation: String {
        let names = score.components.filter { $0.status == .notDisclosed && $0.points.lowerBound < $0.points.upperBound }.map { $0.nutrient.english.lowercased() }
        guard !names.isEmpty else { return "A range, because some printed values are ranges or below the zero threshold." }
        return "A range, because the label doesn't disclose \(ListFormatter.localizedString(byJoining: names)). It could score anywhere in between."
    }
}

private struct BreakdownSection: View {
    var score: HealthScore
    var panel: NutritionPanel

    var body: some View {
        Section("What moved the score") {
            ForEach(score.components) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(c.nutrient.english) \(Text(c.nutrient.japanese).foregroundStyle(.secondary))")
                        Text(valueText(c)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(pointsText(c.points)).monospacedDigit()
                        .foregroundStyle(c.points.upperBound > 0 ? .green : (c.points.lowerBound < -0.5 ? .red : .secondary))
                }
            }
        }
    }

    private func valueText(_ c: HealthScore.Component) -> String {
        switch c.status {
        case .notDisclosed where c.value.upperBound == 0: return "Not disclosed"
        case .notDisclosed: return "Not disclosed · could be 0–\(Format.grams(c.value.upperBound)) g \(panel.basis.per100Label)"
        case .printedZero: return "Printed as 0 · under \(Format.grams(c.value.upperBound)) g \(panel.basis.per100Label)"
        case .stated: return "\(Format.range(c.value)) g \(panel.basis.per100Label)"
        }
    }

    private func pointsText(_ p: ClosedRange<Double>) -> String {
        let f = { (x: Double) in x.rounded() == 0 ? "0" : (x > 0 ? "+" : "−") + "\(Int(abs(x).rounded()))" }
        return Int(p.lowerBound.rounded()) == Int(p.upperBound.rounded()) ? f(p.lowerBound) : "\(f(p.lowerBound)) to \(f(p.upperBound))"
    }
}

/// The label as printed, with %DV from the chosen standard (WHO fills gaps).
private struct LabelSection: View {
    var panel: NutritionPanel
    var dvSource: String

    var body: some View {
        Section {
            ForEach(Nutrient.allCases, id: \.self) { n in
                row(n)
            }
        } header: {
            Text("Label · \(panel.basis.label)")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let salt = panel[.salt], !salt.isPrintedZero {
                    Text("Salt \(Format.range(salt)) g ≈ \(Int(NutritionPanel.sodiumMg(fromSalt: salt.midpoint).rounded())) mg sodium.")
                }
                if panel.values.values.contains(where: \.isPrintedZero) {
                    Text("* A printed 0 means below a threshold per 100 g / ml (e.g. under 5 kcal), not none.")
                }
            }
        }
    }

    @ViewBuilder private func row(_ n: Nutrient) -> some View {
        let amount = panel[n]
        // Optional sub-lines that aren't printed are listed only when they matter for carbs or fat.
        if amount != nil || [.energy, .protein, .fat, .carbohydrate, .salt, .sugars, .fibre].contains(n) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(n.english) \(Text(n.japanese).foregroundStyle(.secondary))")
                    // 糖類 sits under 糖質 when it's printed, otherwise directly under 炭水化物.
                    .padding(.leading, CGFloat(n == .sugars && panel[.netCarbs] == nil ? 1 : n.depth) * 14)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let amount {
                        Text(amount.isPrintedZero ? "0 \(n.unit)*" : "\(Format.range(amount)) \(n.unit)").monospacedDigit()
                        Text(dvText(n, amount)).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Not disclosed").foregroundStyle(.secondary).italic()
                    }
                }
            }
        }
    }

    private func dvText(_ n: Nutrient, _ amount: Amount) -> String {
        guard let pct = DailyValues.shared.percent(for: n, amount: amount.midpoint, panel: panel, sourceKey: dvSource) else {
            return "No reference"
        }
        let base = "\(Int(pct.percent.rounded()))% \(pct.phrase)"
        return pct.fallbackSourceName.map { "\(base) · \($0)" } ?? base
    }
}

/// The carbohydrate bar from docs/ui-domain-context.md §3, with hatching for what isn't disclosed.
private struct CarbSection: View {
    var panel: NutritionPanel

    var body: some View {
        if let carbs = panel[.carbohydrate]?.midpoint, carbs > 0 {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        HStack(spacing: 1) {
                            ForEach(segments(carbs), id: \.label) { s in
                                Group {
                                    if s.hatched { Hatch() } else { Rectangle().fill(s.color) }
                                }
                                .frame(width: max(geo.size.width * s.value / carbs - 1, 2))
                            }
                        }
                    }
                    .frame(height: 18)
                    .clipShape(.rect(cornerRadius: 4))
                    ForEach(segments(carbs), id: \.label) { s in
                        HStack {
                            if s.hatched { Hatch().frame(width: 12, height: 12) } else { RoundedRectangle(cornerRadius: 2).fill(s.color).frame(width: 12, height: 12) }
                            Text(s.label).font(.caption)
                            Spacer()
                            Text("\(Format.grams(s.value)) g").font(.caption).monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Carbohydrate \(Format.grams(carbs)) g · includes fibre")
            } footer: {
                Text(netCarbsText(carbs))
            }
        }
    }

    private struct Segment { var label: String; var value: Double; var color: Color; var hatched = false }

    private func segments(_ c: Double) -> [Segment] {
        let s = panel[.sugars]?.midpoint, net = panel[.netCarbs]?.midpoint, f = panel[.fibre]?.midpoint
        switch panel.carbState {
        case .totalOnly:
            return [Segment(label: "Sugars, starch, fibre: not disclosed", value: c, color: .clear, hatched: true)]
        case .sugarsOnly:
            return [Segment(label: "Sugars", value: s ?? 0, color: .pink),
                    Segment(label: "Starch, fibre, sugar alcohols: split not disclosed", value: max(c - (s ?? 0), 0), color: .clear, hatched: true)]
        case .splitNoSugars:
            return [Segment(label: "Net carbs (sugar share not stated)", value: net ?? 0, color: .orange),
                    Segment(label: "Fibre", value: f ?? 0, color: .green)]
        case .full:
            return [Segment(label: "Sugars", value: s ?? 0, color: .pink),
                    Segment(label: "Other net carbs", value: max((net ?? 0) - (s ?? 0), 0), color: .orange),
                    Segment(label: "Fibre", value: f ?? 0, color: .green)]
        }
    }

    private func netCarbsText(_ c: Double) -> String {
        switch panel.carbState {
        case .totalOnly: "Net carbs: somewhere between 0 and \(Format.grams(c)) g. The label doesn't split it."
        case .sugarsOnly: "Net carbs: \(Format.grams(panel[.sugars]?.midpoint ?? 0))–\(Format.grams(c)) g."
        case .splitNoSugars, .full: "Net carbs 糖質: \(Format.grams(panel[.netCarbs]?.midpoint ?? 0)) g."
        }
    }
}

/// Diagonal stripes: "not disclosed", clearly not a nutrient colour.
private struct Hatch: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.gray.opacity(0.12)))
            var x = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(p, with: .color(.gray.opacity(0.55)), lineWidth: 1.5)
                x += 6
            }
        }
    }
}

private struct BasisAmountSection: View {
    var panel: NutritionPanel
    var scan: Scan?
    @State private var grams = ""

    var body: some View {
        Section {
            Text("The label is per “\(panel.basis.label)” but doesn't say how much that is, so it can't be compared per 100 g yet.")
            if scan != nil {
                HStack {
                    TextField(panel.netContents.map { "e.g. \(Format.grams($0)) (内容量)" } ?? "Weight", text: $grams)
                        .keyboardType(.decimalPad)
                    Text(panel.basis.unit?.rawValue ?? "g").foregroundStyle(.secondary)
                    Button("Score") { scan?.userBasisAmount = Double(grams) }
                        .disabled((Double(grams) ?? 0) <= 0)
                }
            }
        } header: {
            Text("Needs the serving weight")
        } footer: {
            if let net = panel.netContents {
                Text("The pack says 内容量 \(Format.grams(net)). Use that only if the label is per whole pack.")
            }
        }
        .onAppear { grams = panel.netContents.map { Format.grams($0) } ?? "" }
    }
}

enum Format {
    static func grams(_ x: Double) -> String {
        // Never show more precision than labels print: one decimal, two only below 1 g.
        x.formatted(.number.precision(.fractionLength(x < 1 ? 0...2 : 0...1)))
    }

    static func range(_ a: Amount) -> String { a.isRange ? "\(grams(a.min))–\(grams(a.max))" : grams(a.min) }
    static func range(_ r: ClosedRange<Double>) -> String { r.lowerBound == r.upperBound ? grams(r.lowerBound) : "\(grams(r.lowerBound))–\(grams(r.upperBound))" }
}

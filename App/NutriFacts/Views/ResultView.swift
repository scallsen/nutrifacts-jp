import SwiftUI

/// The breakdown of one scan. Used for the live result and for scans opened from History.
struct ResultView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("referenceSource") private var sourceID = ReferenceSource.japan.id
    @AppStorage("showJapanese") private var showJapanese = true
    @State private var basis: Basis = .asLabelled

    let scan: Scan
    var showsScanAgain = true

    private var analysis: PanelAnalysis {
        PanelAnalysis(panel: scan.panel, basis: basis, source: .with(id: sourceID))
    }

    var body: some View {
        let a = analysis
        List {
            ThingsToKnowSection(analysis: a)
            Section {
                Picker("Amount", selection: $basis) {
                    ForEach(a.availableBases) { Text(a.title(for: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text((basis == .asLabelled ? "As labelled " : "Converted from ") + a.panel.basisDescription
                     + (showJapanese ? " · \(a.panel.basisJapanese)" : ""))
            }
            NutritionSection(analysis: a, showJapanese: showJapanese)
            CarbBreakdownSection(analysis: a)
            if !a.labelNotes.isEmpty {
                Section("About this label") {
                    ForEach(a.labelNotes) { NoticeRow(notice: $0) }
                }
            }
            Section {
                NavigationLink {
                    LabelPhotoView(panel: scan.panel)
                } label: {
                    HStack(spacing: 12) {
                        LabelThumbnail(panel: scan.panel)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View Label Photo")
                            Text("Compare with what we read").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Nutrition Facts")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if showsScanAgain {
                Button {
                    model.startScanning()
                } label: {
                    Label("Scan Again", systemImage: "camera").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .onChange(of: scan) { basis = .asLabelled }
    }
}

// MARK: - Things to know

private struct ThingsToKnowSection: View {
    let analysis: PanelAnalysis

    var body: some View {
        Section {
            let warnings = analysis.warnings
            if warnings.isEmpty {
                NoticeRow(notice: Notice(symbol: "checkmark", tint: .green, title: "Nothing high",
                                         detail: "Fat, saturated fat, sugars and salt are medium or low."))
            } else {
                ForEach(warnings) { NoticeRow(notice: $0) }
            }
        } header: {
            Text("Things to know")
        } footer: {
            Text("Levels per 100 \(analysis.panel.unit.rawValue), using UK bands.")
        }
    }
}

struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notice.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(notice.tint.gradient, in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                Text(notice.detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Nutrition

private struct NutritionSection: View {
    let analysis: PanelAnalysis
    let showJapanese: Bool

    var body: some View {
        let p = analysis.panel.printed
        Section {
            NutrientRow(analysis: analysis, key: .energy, depth: 0, showJapanese: showJapanese)
            NutrientRow(analysis: analysis, key: .protein, depth: 0, showJapanese: showJapanese)
            NutrientRow(analysis: analysis, key: .fat, depth: 0, showJapanese: showJapanese)
            NutrientRow(analysis: analysis, key: .saturatedFat, depth: 1, showJapanese: showJapanese)
            NutrientRow(analysis: analysis, key: .carbohydrate, depth: 0, showJapanese: showJapanese, note: "incl. fibre")
            NutrientRow(analysis: analysis, key: .netCarbs, depth: 1, showJapanese: showJapanese)
            NutrientRow(analysis: analysis, key: .sugars, depth: p[.netCarbs] != nil ? 2 : 1, showJapanese: showJapanese)
            NutrientRow(analysis: analysis, key: .fibre, depth: 1, showJapanese: showJapanese)
            NutrientRow(analysis: analysis, key: .salt, depth: 0, showJapanese: showJapanese,
                        note: analysis.sodiumMg.map { "≈ \(Int($0.rounded())) mg sodium" })
        } header: {
            HStack {
                Text("Nutrition")
                Spacer()
                Text(analysis.basisDescription).textCase(nil).fontWeight(.regular)
            }
        } footer: {
            Text(analysis.nutritionFooter(levelsShown: true))
        }
    }
}

/// One label line: English name (and Japanese), the value, then the level and % in the level's colour.
private struct NutrientRow: View {
    let analysis: PanelAnalysis
    let key: NutrientKey
    let depth: Int
    let showJapanese: Bool
    var note: String?

    var body: some View {
        let shown = analysis.value(key)
        let level = shown == nil ? nil : analysis.level(key)
        let percent = analysis.percent(key)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(key.english).font(depth > 0 ? .callout : .body)
                HStack(spacing: 6) {
                    if showJapanese { Text(key.japanese) }
                    if shown?.isCalculated == true { Tag(text: "Calculated", tint: .indigo) }
                    if shown?.isUpperBound == true { Text("printed as 0") }
                    else if let note, shown != nil { Text(note) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(shown?.text ?? "Not listed")
                    .font(depth > 0 ? .callout : .body)
                    .monospacedDigit()
                    .foregroundStyle(shown == nil ? .secondary : .primary)
                if shown != nil {
                    HStack(spacing: 4) {
                        if let level {
                            Text(level.word).fontWeight(.semibold).foregroundStyle(level.color)
                        }
                        if let percent {
                            if level != nil { Text("·").foregroundStyle(.secondary) }
                            Text(percent.text)
                                .fontWeight(level == nil ? .regular : .semibold)
                                .foregroundStyle(level?.color ?? .secondary)
                            if percent.fromWHO { Tag(text: "WHO", tint: .teal) }
                        } else if key != .netCarbs, !analysis.hasReference(key) {
                            Text("No reference").foregroundStyle(.secondary)
                        }
                    }
                    .font(.footnote)
                    .monospacedDigit()
                }
            }
        }
        .padding(.leading, CGFloat(depth) * 16)
        .accessibilityElement(children: .combine)
    }
}

struct Tag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: .rect(cornerRadius: 5))
    }
}

// MARK: - Carbohydrate breakdown

private struct CarbBreakdownSection: View {
    let analysis: PanelAnalysis

    private struct Segment: Identifiable {
        let id = UUID()
        var name: String
        var grams: Double
        var color: Color?
    }

    var body: some View {
        let p = analysis.panel
        let total = p.number(.carbohydrate) ?? 0
        let segments = segments(total: total)
        Section {
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(segments) { segment in
                            let width = max(4, (proxy.size.width - CGFloat(segments.count - 1) * 2) * segment.grams / max(total, 0.01))
                            Group {
                                if let color = segment.color { Rectangle().fill(color) } else { Hatch() }
                            }
                            .frame(width: width)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 8))
                }
                .frame(height: 24)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(segments) { segment in
                        HStack(spacing: 8) {
                            Group {
                                if let color = segment.color { RoundedRectangle(cornerRadius: 3).fill(color) } else { Hatch().clipShape(.rect(cornerRadius: 3)) }
                            }
                            .frame(width: 11, height: 11)
                            Text(segment.name)
                            Spacer()
                            Text(String(format: "%.1f g", segment.grams)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.footnote)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("Carbohydrate breakdown")
                Spacer()
                Text(String(format: "%.1f g", total)).textCase(nil).fontWeight(.regular)
            }
        } footer: {
            Text(footer(total: total))
        }
    }

    private func segments(total: Double) -> [Segment] {
        let p = analysis.panel
        switch analysis.carbState {
        case .totalOnly:
            return [Segment(name: "Not broken down", grams: total)]
        case .sugarsOnly:
            let s = p.number(.sugars) ?? 0
            return [Segment(name: "Sugars", grams: s, color: .pink), Segment(name: "Rest, not broken down", grams: total - s)]
        case .splitNoSugars:
            let net = p.number(.netCarbs) ?? (total - (p.number(.fibre) ?? 0))
            return [Segment(name: "Net carbs", grams: net, color: .orange), Segment(name: "Fibre", grams: total - net, color: .green)]
        case .full:
            let net = p.number(.netCarbs) ?? 0, s = p.number(.sugars) ?? 0, f = p.number(.fibre) ?? 0
            let sweetened = p.ingredients.contains("エリスリトール") || p.ingredients.contains("マルチトール")
            return [Segment(name: "Sugars", grams: s, color: .pink),
                    Segment(name: sweetened ? "Starch and sugar alcohols" : "Starch and other carbs", grams: net - s, color: .orange),
                    Segment(name: "Fibre", grams: f, color: .green)]
        }
    }

    private func footer(total: Double) -> String {
        switch analysis.carbState {
        case .totalOnly: return "Only the total is listed."
        case .sugarsOnly:
            let s = analysis.panel.number(.sugars) ?? 0
            return String(format: "Fibre isn’t listed, so net carbs are %.1f–%.1f g.", s, total)
        case .splitNoSugars: return "Sugars aren’t split out of net carbs."
        case .full: return "Net carbs = carbohydrate minus fibre."
        }
    }
}

/// Diagonal hatching for "not broken down".
private struct Hatch: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.secondary.opacity(0.12)))
            var x: CGFloat = -size.height
            while x < size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height))
                line.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(line, with: .color(.secondary.opacity(0.35)), lineWidth: 2)
                x += 7
            }
        }
    }
}

struct LabelThumbnail: View {
    let panel: LabelPanel

    var body: some View {
        PrintedLabelView(panel: panel)
            .frame(width: 220)
            .scaleEffect(0.26, anchor: .topLeading)
            .frame(width: 48, height: 48, alignment: .topLeading)
            .padding(4)
            .background(LinearGradient(colors: panel.packColors.map(Color.init(hex:)), startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(.rect(cornerRadius: 9))
    }
}

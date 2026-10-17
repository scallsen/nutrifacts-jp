import SwiftUI

/// The breakdown of one scan. Used for the live result and for scans opened from History.
struct ResultView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("referenceSource") private var sourceID = ReferenceSource.japan.id
    @AppStorage("showJapanese") private var showJapanese = false
    @State private var basis: Basis = .asLabelled
    @State private var editingPack = false
    @State private var packText = ""

    let scan: Scan
    var showsScanAgain = true

    private var analysis: PanelAnalysis {
        PanelAnalysis(panel: model.latest(scan).panel, basis: basis, source: .with(id: sourceID))
    }

    var body: some View {
        let a = analysis
        List {
            if !a.knowsBasisAmount { BasisSizeSection(panel: a.panel, scan: model.latest(scan)) }
            if model.latest(scan).readBy == .onDevice {
                Section {
                    NoticeRow(notice: Notice(symbol: "iphone", tint: .orange, title: "Read on this iPhone",
                                             detail: "Private Cloud Compute wasn't available, so the smaller on-device model read this label. Check the numbers against the photo."))
                }
            }
            ThingsToKnowSection(analysis: a)
            Section {
                Picker("Amount", selection: $basis) {
                    ForEach(a.availableBases) { Text(a.title(for: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if a.knowsBasisAmount {
                Section {
                    Button {
                        packText = a.panel.packAmount.map { NumberFormat.amount($0, .protein) } ?? ""
                        editingPack = true
                    } label: {
                        LabeledContent("Pack Size",
                                       value: a.panel.packAmount.map { "\(NumberFormat.amount($0, .protein)) \(a.panel.unit.rawValue)" } ?? "Add")
                    }
                    .tint(.primary)
                }
            }
            NutritionSection(analysis: a, showJapanese: showJapanese)
            CarbBreakdownSection(analysis: a)
            if !a.labelNotes.isEmpty {
                Section("About this label") {
                    ForEach(a.labelNotes) { NoticeRow(notice: $0) }
                }
            }
            #if DEBUG
            if let timing = model.latest(scan).timing {
                TimingSection(timing: timing)
            }
            #endif
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
        .alert("Pack Size", isPresented: $editingPack) {
            TextField("Size in \(analysis.panel.unit.rawValue)", text: $packText).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Done") { setPack() }
        } message: {
            Text("The whole pack, printed as 内容量 (net contents), e.g. 500 \(analysis.panel.unit.rawValue).")
        }
    }

    private func setPack() {
        guard let amount = Double(packText.replacingOccurrences(of: ",", with: ".")), amount > 0 else { return }
        model.setPackSize(of: scan, amount: amount)
        if analysis.availableBases.contains(.wholePack) { basis = .wholePack }
    }
}

// MARK: - Things to know

private struct ThingsToKnowSection: View {
    let analysis: PanelAnalysis

    var body: some View {
        Section {
            let warnings = analysis.warnings
            if !analysis.knowsBasisAmount {
                NoticeRow(notice: Notice(symbol: "questionmark", tint: .orange, title: "Levels need the size of \(analysis.panel.basisUnitName)",
                                         detail: "High and low are per 100 \(analysis.panel.unit.rawValue). Add the size above."))
                ForEach(warnings) { NoticeRow(notice: $0) }
            } else if warnings.isEmpty {
                NoticeRow(notice: Notice(symbol: "checkmark", tint: .green, title: "Nothing high",
                                         detail: "Fat, saturated fat, sugars and salt are medium or low."))
            } else {
                ForEach(warnings) { NoticeRow(notice: $0) }
            }
        } header: {
            Text("Things to know")
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
                    if shown?.isCalculated == true { Text("Calculated") }
                    else if analysis.panel.isEstimate, shown != nil { Text("Estimated") }
                    if let note, shown != nil, level != .zero { Text(note) }
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
                        if level == .zero {
                            // "Low" says it all; a % of a "0" line isn't meaningful.
                        } else if let percent {
                            if level != nil { Text("·").foregroundStyle(.secondary) }
                            Text(percent.text)
                                .fontWeight(level == nil ? .regular : .semibold)
                                .foregroundStyle(level?.color ?? .secondary)
                            if percent.fromWHO { Text("WHO").foregroundStyle(.secondary) }
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
        /// Grey for carbohydrate the label doesn't break down.
        var color: Color = Color(.systemGray3)
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
                            let available = proxy.size.width - CGFloat(segments.count - 1) * 2
                            let width = total > 0 ? max(4, available * segment.grams / total) : available / CGFloat(segments.count)
                            Rectangle().fill(segment.color)
                                .frame(width: width)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 8))
                }
                .frame(height: 24)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(segments) { segment in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(segment.color)
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
        }
    }

    private func segments(total: Double) -> [Segment] {
        let p = analysis.panel
        if p.number(.carbohydrate) == 0 { return [Segment(name: "Low (printed as 0)", grams: 0, color: .green.opacity(0.35))] }
        switch analysis.carbState {
        case .totalOnly:
            return [Segment(name: "Unknown carbohydrates", grams: total)]
        case .sugarsOnly:
            let s = p.number(.sugars) ?? 0
            return [Segment(name: "Sugars", grams: s, color: .pink), Segment(name: "Unknown carbohydrates", grams: total - s)]
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
}

struct LabelThumbnail: View {
    let panel: LabelPanel

    var body: some View {
        if let data = panel.photo, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 9))
        } else {
            drawn
        }
    }

    private var drawn: some View {
        PrintedLabelView(panel: panel)
            .frame(width: 220)
            .scaleEffect(0.26, anchor: .topLeading)
            .frame(width: 48, height: 48, alignment: .topLeading)
            .padding(4)
            .background(LinearGradient(colors: panel.packColors.map(Color.init(hex:)), startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(.rect(cornerRadius: 9))
    }
}

#if DEBUG
/// Where the time went for this scan. Debug builds only; Settings › Share Logs has it in every build.
private struct TimingSection: View {
    let timing: ScanTiming

    var body: some View {
        Section("Timing (debug)") {
            if let capture = timing.capture { row("Capture", ScanTiming.seconds(capture)) }
            row("Prepare", ScanTiming.seconds(timing.prepare))
            row("Read", ScanTiming.seconds(timing.read))
            ForEach(timing.details, id: \.self) { row("  \($0.name)", $0.value) }
            row("Crop wait", ScanTiming.seconds(timing.cropWait))
            row("Total", ScanTiming.seconds(timing.total))
            row("Image", timing.imageSize)
        }
        .font(.footnote)
    }

    private func row(_ name: String, _ value: String) -> some View {
        LabeledContent(name) { Text(value).monospacedDigit() }
    }
}
#endif

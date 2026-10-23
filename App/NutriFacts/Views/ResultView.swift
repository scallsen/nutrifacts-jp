import SwiftUI

/// The breakdown of one scan. Used for the live result and for scans opened from History.
struct ResultView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("referenceSource") private var sourceID = ReferenceSource.japan.id
    @AppStorage("showJapanese") private var showJapanese = false
    @AppStorage("showsScanTiming") private var showsTiming = false
    /// The amount picked in the size tabs. Until one is picked, `PanelAnalysis.defaultBasis`, so a result
    /// moves to the whole pack when the ingredients box brings its size.
    @State private var pickedBasis: Basis?
    /// The pieces, servings or packs picked in the stepper. Until one is picked, `defaultCount`.
    @State private var pickedCount: Int?
    @State private var editingWeight = false
    @State private var weightText = ""
    @State private var editingPack = false
    @State private var packText = ""
    @State private var copied = false
    @State private var addedToHealth = false
    @State private var healthError: String?

    let scan: Scan
    var showsScanAgain = true

    private var basis: Basis {
        let panel = model.latest(scan).panel
        if let pickedBasis, PanelAnalysis.availableBases(for: panel).contains(pickedBasis) { return pickedBasis }
        return PanelAnalysis.defaultBasis(for: panel)
    }

    private var count: Int { pickedCount ?? defaultCount }

    /// The whole pack, when a step is smaller than the label's amount (one piece of a label per pack of 6)
    /// and there's no Pack tab for it. Otherwise one.
    private var defaultCount: Int {
        let panel = model.latest(scan).panel
        guard !PanelAnalysis.availableBases(for: panel).contains(.wholePack), let pieces = panel.portion?.perPack else { return 1 }
        return pieces
    }

    private var analysis: PanelAnalysis {
        PanelAnalysis(panel: model.latest(scan).panel, basis: basis, source: .with(id: sourceID), count: count)
    }

    var body: some View {
        let a = analysis
        ScrollViewReader { proxy in
            List {
                if model.latest(scan).readBy == .onDevice {
                    Section {
                        NoticeRow(notice: Notice(symbol: "iphone", tint: .orange, title: "Read on this iPhone",
                                                 detail: "Private Cloud Compute wasn't available, so the smaller on-device model read this label. Check the numbers against the photo."))
                    }
                }
                ThingsToKnowSection(analysis: a)
                if a.availableBases.count > 1 {
                    Section {
                        Picker("Amount", selection: Binding(get: { basis }, set: { pickedBasis = $0 })) {
                            ForEach(a.availableBases) { Text(a.title(for: $0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        if !showsCount(a), let note = a.basisNote { Text(note) }
                    }
                }
                if showsCount(a), let portion = a.portion { countSection(a, portion) }
                // On every tab, so a pack counted from 内容量 (6個入) can still be given its weight.
                if !a.knowsBasisAmount { weightSection(a) }
                if a.knowsBasisAmount {
                    Section {
                        Button {
                            packText = a.panel.packAmount.map { NumberFormat.amount($0, .protein) } ?? ""
                            editingPack = true
                        } label: {
                            LabeledContent("Whole Pack",
                                           value: a.panel.packAmount.map { "\(NumberFormat.amount($0, .protein)) \(a.panel.unit.rawValue)" } ?? "Add Size")
                        }
                        .tint(.primary)
                    } footer: {
                        if a.panel.packAmount == nil {
                            Text("The pack size isn't in the photo. It's printed as 内容量 (net contents), often in the ingredients box.")
                        } else if a.availableBases.count == 1, let note = a.basisNote {
                            Text(note)
                        }
                    }
                }
                NutritionSection(analysis: a, showJapanese: showJapanese)
                CarbBreakdownSection(analysis: a)
                IngredientsSection(scan: model.latest(scan), showJapanese: showJapanese)
                if !a.labelNotes.isEmpty {
                    Section("About this label") {
                        ForEach(a.labelNotes) { NoticeRow(notice: $0) }
                    }
                }
                Section {
                    let food = NutritionExport.customFood(model.latest(scan), analysis: a)
                    Button {
                        UIPasteboard.general.string = food
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy Nutrition", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .sensoryFeedback(.success, trigger: copied) { _, new in new }
                    // Lets the button copy again, e.g. after picking another amount.
                    .task(id: copied) {
                        guard copied else { return }
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                    ShareLink(item: food) { Label("Share Nutrition", systemImage: "square.and.arrow.up") }
                    if HealthLog.isAvailable {
                        Button {
                            Task {
                                do {
                                    try await HealthLog.add(model.latest(scan), analysis: a)
                                    addedToHealth = true
                                } catch {
                                    healthError = error.localizedDescription
                                }
                            }
                        } label: {
                            Label(addedToHealth ? "Added to Health" : "Add to Apple Health", systemImage: addedToHealth ? "checkmark" : "heart")
                        }
                        .disabled(addedToHealth)
                        .sensoryFeedback(.success, trigger: addedToHealth) { _, new in new }
                        .task(id: addedToHealth) {
                            guard addedToHealth else { return }
                            try? await Task.sleep(for: .seconds(2))
                            addedToHealth = false
                        }
                    }
                } footer: {
                    Text(HealthLog.isAvailable ? "Uses the amount selected above. Health logs it as eaten now." : "Uses the amount selected above.")
                }
                #if DEBUG
                if showsTiming, let timing = model.latest(scan).timing {
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
                    let latest = model.latest(scan)
                    if let box = latest.box, let photo = latest.boxPhoto {
                        NavigationLink {
                            BoxPhotoView(box: box, photo: photo)
                        } label: {
                            HStack(spacing: 12) {
                                PhotoThumbnail(data: photo)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("View Ingredients Photo")
                                    Text("Compare with what we read").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            // One even gap between sections, and no padding around the size tabs' row.
            .listSectionSpacing(.compact)
            .environment(\.defaultMinListRowHeight, 0)
            .onAppear { scrollToIngredients(proxy) }
            .onChange(of: model.scrollToIngredients) { scrollToIngredients(proxy) }
        }
        .navigationTitle(model.latest(scan).title ?? "Nutrition Facts")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if showsScanAgain {
                VStack(spacing: 10) {
                    let latest = model.latest(scan)
                    if latest.box == nil, model.readingBoxFor != scan.id {
                        Button {
                            model.scanIngredients(for: latest)
                        } label: {
                            Label("Scan Ingredients", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                    Button {
                        model.startScanning()
                    } label: {
                        Label("New Scan", systemImage: "camera").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .onChange(of: scan.id) { pickedBasis = nil; pickedCount = nil; copied = false }
        .onChange(of: basis) { copied = false }
        .onChange(of: count) { copied = false }
        .alert("Couldn't Add to Health", isPresented: Binding(get: { healthError != nil }, set: { if !$0 { healthError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(healthError ?? "")
        }
        .alert("Weight of \(weightSubject(analysis))", isPresented: $editingWeight) {
            TextField("Weight in \(analysis.panel.unit.rawValue)", text: $weightText).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Done") { setWeight() }
        } message: {
            Text("Sometimes printed next to the basis, as in 1個（25g）, or as 内容量 (net contents). With it, the label can be compared per 100 \(analysis.panel.unit.rawValue).")
        }
        .alert("Pack Size", isPresented: $editingPack) {
            TextField("Size in \(analysis.panel.unit.rawValue)", text: $packText).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Done") { setPack() }
        } message: {
            Text("The whole pack, printed as 内容量 (net contents), e.g. 500 \(analysis.panel.unit.rawValue).")
        }
    }

    /// After an ingredients scan, brings the new box into view once the sheet has settled.
    private func scrollToIngredients(_ proxy: ScrollViewProxy) {
        guard model.scrollToIngredients == scan.id else { return }
        model.scrollToIngredients = nil
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.snappy) { proxy.scrollTo(IngredientsSection.anchor, anchor: .top) }
        }
    }

    /// The stepper is for counting what the label's amount describes: pieces, servings or packs.
    private func showsCount(_ a: PanelAnalysis) -> Bool { a.basis == .asLabelled && a.portion != nil }

    /// "2 pieces", with whether that's the whole pack and its weight.
    private func countSection(_ a: PanelAnalysis, _ portion: Portion) -> some View {
        Section {
            // A pack can hold more than 99, e.g. 120粒 opens on all of them.
            Stepper(value: Binding(get: { count }, set: { pickedCount = $0 }), in: 1...max(99, defaultCount)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(portion.text(count)).monospacedDigit()
                    if let detail = amountDetail(a, portion) {
                        Text(detail).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        } footer: {
            if let note = a.basisNote { Text(note) }
        }
    }

    /// The label's weight when it isn't printed: the 内容量 suggestion to confirm, or typed in. Optional.
    private func weightSection(_ a: PanelAnalysis) -> some View {
        Section {
            if let suggestion = a.panel.basisSuggestion {
                Button {
                    model.confirmBasis(of: scan, amount: suggestion.amount, unit: suggestion.unit)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use \(NumberFormat.amount(suggestion.amount, .protein)) \(suggestion.unit.rawValue) for \(weightSubject(a))")
                        Text("From \(suggestion.reason). Check it: a pack can hold several pieces.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                weightText = ""
                editingWeight = true
            } label: {
                LabeledContent("Weight", value: "Add")
            }
            .tint(.primary)
        } footer: {
            Text("The weight isn't printed. It's only needed to compare per 100 \(a.panel.unit.rawValue).")
        }
    }

    /// "Whole pack · 120 g", "6 in the pack".
    private func amountDetail(_ a: PanelAnalysis, _ portion: Portion) -> String? {
        var parts: [String] = []
        if let pieces = portion.perPack {
            parts.append(a.count == pieces ? "Whole pack" : "\(pieces) in the pack")
        }
        if let amount = a.targetAmount { parts.append("\(NumberFormat.amount(amount, .protein)) \(a.panel.unit.rawValue)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What a typed weight is the weight of: one piece, the pack, or the label's amount (2枚).
    private func weightSubject(_ a: PanelAnalysis) -> String {
        if let portion = a.portion, portion.ofBasis == 1 { return "1 \(portion.singular)" }
        return a.panel.basisIsWholePack ? "the pack" : a.panel.basisUnitName
    }

    private func setWeight() {
        guard let amount = Double(weightText.replacingOccurrences(of: ",", with: ".")), amount > 0 else { return }
        model.confirmBasis(of: scan, amount: amount, unit: analysis.panel.unit)
    }

    private func setPack() {
        guard let amount = Double(packText.replacingOccurrences(of: ",", with: ".")), amount > 0 else { return }
        model.setPackSize(of: scan, amount: amount)
        pickedBasis = .wholePack
    }
}

// MARK: - Ingredients

/// The ingredients box (一括表示) from a second scan. The Scan Ingredients button floats at the bottom.
private struct IngredientsSection: View {
    @Environment(AppModel.self) private var model
    let scan: Scan
    let showJapanese: Bool

    @State private var showsOther = false

    /// Scrolled to after an ingredients scan.
    static let anchor = "ingredients"

    var body: some View {
        if let box = scan.box {
            Section("Ingredients") {
                AllergenRow(allergens: box.allergens, showJapanese: showJapanese)
                    .id(Self.anchor)
            }
            let (ingredients, additives) = (box.ingredients.filter { !$0.isAdditive }, box.ingredients.filter(\.isAdditive))
            if !ingredients.isEmpty {
                Section {
                    ForEach(Array(ingredients.enumerated()), id: \.offset) { ingredientRow($1) }
                } footer: {
                    Text("Listed in order of quantity")
                }
            }
            if !additives.isEmpty {
                Section("Additives") {
                    ForEach(Array(additives.enumerated()), id: \.offset) { ingredientRow($1) }
                }
            }
            Section {
                Button {
                    withAnimation { showsOther.toggle() }
                } label: {
                    HStack {
                        Text(showsOther ? "Hide Other Contents" : "Show Other Contents")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showsOther ? 90 : 0))
                    }
                }
                if showsOther {
                    if !box.netContentsText.isEmpty {
                        LabeledContent("Net Contents", value: box.netContentsPrintedElsewhere ? "Printed elsewhere" : box.netContentsText)
                    }
                    row("Food Type", box.category)
                    row(box.isUseBy ? "Use By" : "Best Before", box.date)
                    row("Storage", box.storage)
                    row("Country of Origin", box.countryOfOrigin)
                    if !box.maker.isEmpty {
                        LabeledContent("Made By") { Text(box.maker).multilineTextAlignment(.trailing) }
                    }
                }
            }
        } else if model.readingBoxFor == scan.id {
            Section("Ingredients") {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the ingredients…").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The English name, with anything in brackets on its own line: "Chocolate chips" over "sugar, cocoa mass".
    private func ingredientRow(_ item: ExtractedIngredient) -> some View {
        let (name, detail) = Self.split(item.english.isEmpty ? item.japanese : item.english)
        return VStack(alignment: .leading, spacing: 2) {
            Text(name)
            if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            if showJapanese && !item.english.isEmpty { Text(item.japanese).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    /// "chocolate chips (sugar, cocoa mass)" → ("Chocolate chips", "sugar, cocoa mass").
    static func split(_ text: String) -> (String, String?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.firstIndex(where: { $0 == "(" || $0 == "（" }), open != trimmed.startIndex,
              let last = trimmed.last, last == ")" || last == "）" else { return (capitalised(trimmed), nil) }
        let name = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        let detail = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)].trimmingCharacters(in: .whitespaces)
        return (capitalised(name), detail.isEmpty ? nil : detail)
    }

    private static func capitalised(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    @ViewBuilder
    private func row(_ title: String, _ text: TranslatedText) -> some View {
        if !text.japanese.isEmpty {
            LabeledContent(title) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(text.english.isEmpty ? text.japanese : text.english)
                    if showJapanese && !text.english.isEmpty { Text(text.japanese).font(.footnote) }
                }
                .multilineTextAlignment(.trailing)
            }
        }
    }
}

/// "Contains wheat, egg, milk" as a warning, in the Things to know style. Only what the pack names.
private struct AllergenRow: View {
    let allergens: [String]
    let showJapanese: Bool

    var body: some View {
        let names = allergens.map { ExtractedIngredientsBox.allergenName($0) }
        HStack(spacing: 12) {
            Image(systemName: allergens.isEmpty ? "minus" : "exclamationmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background((allergens.isEmpty ? Color.gray : .orange).gradient, in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(allergens.isEmpty ? "No allergens listed" : "Contains " + ListFormatter.localizedString(byJoining: names.map { $0.lowercased() }))
                if showJapanese && !allergens.isEmpty {
                    Text(allergens.joined(separator: "・")).font(.footnote).foregroundStyle(.secondary)
                }
                Text("A missing allergen is not a guarantee it's free of them").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Things to know

private struct ThingsToKnowSection: View {
    let analysis: PanelAnalysis

    var body: some View {
        let warnings = analysis.warnings
        if analysis.source.rule == nil {
            if !warnings.isEmpty {
                Section("Things to know") { ForEach(warnings) { NoticeRow(notice: $0) } }
            }
        } else {
            levelsSection(warnings)
        }
    }

    private func levelsSection(_ warnings: [Notice]) -> some View {
        Section {
            // The FDA and Canada judge a serving, so a label per 1個 needs no weight. The UK's notice asks for one.
            if let notice = analysis.guidanceNotice { NoticeRow(notice: notice) }
            ForEach(warnings) { NoticeRow(notice: $0) }
        } header: {
            Text("Things to know")
        }
    }
}

struct NoticeRow: View {
    let notice: Notice
    @State private var showsInfo = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notice.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(notice.tint.gradient, in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(notice.title)
                    if let info = notice.info {
                        Button("About this estimate", systemImage: "info.circle") { showsInfo = true }
                            .labelStyle(.iconOnly)
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                            .popover(isPresented: $showsInfo) {
                                Text(info)
                                    .font(.footnote)
                                    .padding()
                                    .frame(idealWidth: 260)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .presentationCompactAdaptation(.popover)
                            }
                    }
                }
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
            Text(analysis.nutritionFooter)
        }
    }
}

/// One label line: English name (and Japanese), the value, then the chosen authority's words and the % in their colour.
private struct NutrientRow: View {
    let analysis: PanelAnalysis
    let key: NutrientKey
    let depth: Int
    let showJapanese: Bool
    var note: String?

    var body: some View {
        let shown = analysis.value(key)
        let verdict = shown == nil ? nil : analysis.verdict(key)
        let percent = analysis.percent(key)
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(key.english)
                HStack(spacing: 6) {
                    if showJapanese { Text(key.japanese) }
                    if shown?.isCalculated == true { Text("Calculated") }
                    else if analysis.panel.isEstimate, shown != nil { Text("Estimated") }
                    if let note, shown != nil, shown?.isUpperBound != true { Text(note) }
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(shown?.text ?? "Not listed")
                    .monospacedDigit()
                    .foregroundStyle(shown == nil ? .secondary : .primary)
                if shown == nil, analysis.mayBeHigh(key) {
                    Text("May be high").fontWeight(.semibold).foregroundStyle(.orange)
                } else if shown != nil {
                    HStack(spacing: 4) {
                        if let verdict {
                            Text(verdict.text).fontWeight(.semibold).foregroundStyle(verdict.color)
                        }
                        if let percent {
                            if verdict != nil { Text("·").foregroundStyle(.secondary) }
                            Text(percent.text)
                                .fontWeight(verdict == nil ? .regular : .semibold)
                                .foregroundStyle(verdict?.color ?? .secondary)
                            if percent.fromWHO { Text("WHO").foregroundStyle(.secondary) }
                        } else if key != .netCarbs, !analysis.hasReference(key) {
                            Text("No reference").foregroundStyle(.secondary)
                        }
                    }
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

/// A small square crop of a photo, for the rows that open one.
struct PhotoThumbnail: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 9))
        } else {
            RoundedRectangle(cornerRadius: 9).fill(.quaternary).frame(width: 56, height: 56)
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

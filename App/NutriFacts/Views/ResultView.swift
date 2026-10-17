import SwiftUI

/// The breakdown of one scan. Used for the live result and for scans opened from History.
struct ResultView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("referenceSource") private var sourceID = ReferenceSource.japan.id
    @AppStorage("showJapanese") private var showJapanese = false
    @AppStorage("showsScanTiming") private var showsTiming = false
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
            if a.availableBases.count > 1 {
                Section {
                    Picker("Amount", selection: $basis) {
                        ForEach(a.availableBases) { Text(a.title(for: $0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
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
            IngredientsSection(scan: model.latest(scan), showJapanese: showJapanese, canScan: showsScanAgain)
            if !a.labelNotes.isEmpty {
                Section("About this label") {
                    ForEach(a.labelNotes) { NoticeRow(notice: $0) }
                }
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
            }
        }
        // One even gap between sections, and no padding around the size tabs' row.
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListRowHeight, 0)
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

// MARK: - Ingredients

/// The ingredients box (一括表示) from a second scan, or a button to scan it.
private struct IngredientsSection: View {
    @Environment(AppModel.self) private var model
    let scan: Scan
    let showJapanese: Bool
    let canScan: Bool

    @State private var showsOther = false

    var body: some View {
        if let box = scan.box {
            Section("Ingredients") {
                AllergenRow(allergens: box.allergens, showJapanese: showJapanese)
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
        } else if canScan {
            Section {
                Button("Scan Ingredients", systemImage: "list.bullet.rectangle") { model.scanIngredients(for: scan) }
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

    /// English names for the 28 allergens Japan lists (8 required, 20 recommended). Unknown words stay as printed.
    static func allergenName(_ japanese: String) -> String {
        let names = ["えび": "Shrimp", "かに": "Crab", "くるみ": "Walnut", "小麦": "Wheat", "そば": "Buckwheat",
                     "卵": "Egg", "乳": "Milk", "乳成分": "Milk", "落花生": "Peanut", "ピーナッツ": "Peanut",
                     "アーモンド": "Almond", "あわび": "Abalone", "いか": "Squid", "いくら": "Salmon roe",
                     "オレンジ": "Orange", "カシューナッツ": "Cashew", "キウイフルーツ": "Kiwi", "牛肉": "Beef",
                     "ごま": "Sesame", "さけ": "Salmon", "さば": "Mackerel", "大豆": "Soy", "鶏肉": "Chicken",
                     "バナナ": "Banana", "豚肉": "Pork", "まつたけ": "Matsutake", "もも": "Peach",
                     "やまいも": "Yam", "りんご": "Apple", "ゼラチン": "Gelatin"]
        let key = japanese.trimmingCharacters(in: .whitespaces)
        return names[key] ?? key
    }
}

/// "Contains wheat, egg, milk" as a warning, in the Things to know style. Only what the pack names.
private struct AllergenRow: View {
    let allergens: [String]
    let showJapanese: Bool

    var body: some View {
        let names = allergens.map { IngredientsSection.allergenName($0) }
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
        let textFont: Font = depth > 0 ? .callout : .body
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(key.english).font(textFont)
                HStack(spacing: 6) {
                    if showJapanese { Text(key.japanese) }
                    if shown?.isCalculated == true { Text("Calculated") }
                    else if analysis.panel.isEstimate, shown != nil { Text("Estimated") }
                    if let note, shown != nil, level != .zero { Text(note) }
                }
                .font(textFont)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(shown?.text ?? "Not listed")
                    .font(textFont)
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
                    .font(textFont)
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

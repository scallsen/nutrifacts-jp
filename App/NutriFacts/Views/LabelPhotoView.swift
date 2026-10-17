import SwiftUI

/// The captured panel next to what was read from it. Tapping a line highlights it on the photo.
struct LabelPhotoView: View {
    let panel: LabelPanel
    @State private var selected: String?

    var body: some View {
        List {
            if let data = panel.photo, let image = UIImage(data: data) {
                Section {
                    Image(uiImage: image).resizable().scaledToFit()
                        .listRowInsets(EdgeInsets())
                }
            } else {
                drawnLabel
            }
            linesSection
        }
        .navigationTitle("Label Photo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var drawnLabel: some View {
        Section {
            PrintedLabelView(panel: panel, highlighted: selected.map { [$0] } ?? [])
                .frame(maxWidth: 300)
                .rotationEffect(.degrees(-1.2))
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(LinearGradient(colors: panel.packColors.map(Color.init(hex:)), startPoint: .topLeading, endPoint: .bottomTrailing))
                .listRowInsets(EdgeInsets())
                .animation(.default, value: selected)
        }
    }

    private var linesSection: some View {
        Section {
            ForEach(lines, id: \.id) { line in
                Button {
                    selected = selected == line.highlight ? nil : line.highlight
                } label: {
                    // Plain colours: inside a Button, hierarchical styles pick up the tint.
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.japanese).foregroundStyle(Color.primary)
                            Text(line.english).font(.footnote).foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        Text(line.value).foregroundStyle(line.isListed ? Color.primary : Color.secondary).monospacedDigit()
                    }
                    .padding(.leading, CGFloat(line.depth) * 16)
                }
                .allowsHitTesting(line.highlight != nil)
                .listRowBackground(selected != nil && selected == line.highlight ? Color.yellow.opacity(0.18) : nil)
            }
        } header: {
            Text("What we read")
        } footer: {
            Text(panel.photo == nil ? "Tap a line to find it in the photo." : "Compare these with the photo.")
        }
    }

    /// `highlight` is the printed row to mark on the drawn label, if the line is on it.
    private struct Line {
        var id: String
        var japanese: String
        var english: String
        var value: String
        var depth = 0
        var isListed = true
        var highlight: String?
    }

    /// Every line the app understands, in panel order. Lines the label leaves out show "Not listed".
    private var lines: [Line] {
        let rows = PrintedLabelView(panel: panel).rows
        let p = panel.printed
        var result = [Line(id: "head", japanese: "栄養成分表示（\(panel.basisJapanese)）", english: "Nutrition facts",
                           value: panel.basisDescription, highlight: "head")]
        for key in NutrientKey.allCases {
            let printed = p[key] ?? (panel.groupedZeros.contains(key) ? "0" : nil)
            let depth: Int = switch key {
            case .saturatedFat, .netCarbs, .fibre: 1
            case .sugars: p[.netCarbs] != nil ? 2 : 1
            default: 0
            }
            result.append(Line(id: key.rawValue, japanese: key.japanese, english: key.english,
                               value: printed.map { "\($0) \(key.unit)" } ?? "Not listed", depth: depth,
                               isListed: printed != nil,
                               highlight: rows.first { $0.id.split(separator: " ").contains(Substring(key.rawValue)) }?.id))
        }
        if panel.isEstimate {
            result.append(Line(id: "estimate", japanese: "推定値", english: "Estimated values", value: "", highlight: "estimate"))
        }
        return result
    }
}

/// The ingredients box photo next to what was read from it, to check the reading.
struct BoxPhotoView: View {
    let box: ExtractedIngredientsBox
    let photo: Data

    var body: some View {
        List {
            if let image = UIImage(data: photo) {
                Section {
                    Image(uiImage: image).resizable().scaledToFit()
                        .listRowInsets(EdgeInsets())
                }
            }
            Section {
                line("原材料名", "Ingredients", "")
                ForEach(Array(box.ingredients.enumerated()), id: \.offset) { _, item in
                    line(item.japanese, item.english, item.isAdditive ? "Additive" : "")
                        .padding(.leading, 16)
                }
                if !box.allergens.isEmpty {
                    line(box.allergens.joined(separator: "・"), "Allergens listed", "")
                }
                field("名称", "Food type", box.category)
                if !box.netContentsText.isEmpty { line(box.netContentsText, "Net contents (内容量)", "") }
                field(box.isUseBy ? "消費期限" : "賞味期限", box.isUseBy ? "Use by" : "Best before", box.date)
                field("保存方法", "Storage", box.storage)
                field("原産国名", "Country of origin", box.countryOfOrigin)
                if !box.maker.isEmpty { line(box.maker, "Made by", "") }
            } header: {
                Text("What we read")
            } footer: {
                Text("Compare these with the photo. The English is a translation.")
            }
        }
        .navigationTitle("Ingredients Photo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func line(_ japanese: String, _ english: String, _ value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(japanese)
                Text(english).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func field(_ heading: String, _ english: String, _ text: TranslatedText) -> some View {
        if !text.japanese.isEmpty {
            line("\(heading)：\(text.japanese)", text.english.isEmpty ? english : "\(english): \(text.english)", "")
        }
    }
}

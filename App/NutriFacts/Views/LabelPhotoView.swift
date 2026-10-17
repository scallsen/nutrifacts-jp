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
        .toolbar {
            Button("Edit") {}
                .disabled(true)
        }
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
                    selected = selected == line.id ? nil : line.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.english).foregroundStyle(.primary)
                            Text(line.japanese).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(line.value).foregroundStyle(.primary).monospacedDigit()
                    }
                }
                .listRowBackground(selected == line.id ? Color.yellow.opacity(0.18) : nil)
            }
        } header: {
            Text("What we read")
        } footer: {
            Text(panel.photo == nil ? "Tap a line to find it in the photo." : "Compare these with the photo.")
        }
    }

    private struct Line { var id: String; var english: String; var japanese: String; var value: String }

    private var lines: [Line] {
        let label = PrintedLabelView(panel: panel)
        var result = [Line(id: "head", english: "Nutrition facts", japanese: "栄養成分表示（\(panel.basisJapanese)）", value: panel.basisDescription)]
        for row in label.rows {
            let keys = row.id.split(separator: " ").compactMap { NutrientKey(rawValue: String($0)) }
            let english = keys.map(\.english).joined(separator: " and ")
            let unit = keys.first == .energy ? "kcal" : "g"
            let number = row.value.replacingOccurrences(of: unit, with: "")
            result.append(Line(id: row.id, english: english, japanese: "\(row.name) \(row.value)",
                               value: "\(number) \(unit)" + (keys.count > 1 ? " each" : "")))
        }
        if panel.isEstimate { result.append(Line(id: "estimate", english: "Estimated values", japanese: "推定値", value: "")) }
        return result
    }
}

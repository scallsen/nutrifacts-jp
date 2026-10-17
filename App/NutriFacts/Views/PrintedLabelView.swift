import SwiftUI

/// The panel as printed on the pack, in Japanese. Used for the camera placeholder and the label photo.
struct PrintedLabelView: View {
    let panel: LabelPanel
    /// Lines to highlight, matched by nutrient. "head" and "estimate" are also allowed.
    var highlighted: Set<String> = []

    var body: some View {
        Group {
            if panel.layout == .inline { inline } else { table }
        }
        .foregroundStyle(.black)
        .background(Color(white: 0.99))
        .overlay(Rectangle().stroke(.black, lineWidth: 1.5))
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("栄養成分表示").font(.system(size: 12, weight: .bold))
                Spacer()
                Text(panel.basisJapanese).font(.system(size: 10))
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(mark("head"))
            Rectangle().frame(height: 1.5)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Rectangle().fill(.black.opacity(0.3)).frame(height: 1) }
                HStack {
                    Text((row.depth > 0 ? "－" : "") + row.name)
                    Spacer()
                    Text(row.value)
                }
                .font(.system(size: 11))
                .padding(.leading, 6 + CGFloat(row.depth) * 8).padding(.trailing, 6).padding(.vertical, 2.5)
                .background(mark(row.id))
            }
            if panel.isEstimate {
                Rectangle().fill(.black.opacity(0.3)).frame(height: 1)
                Text("推定値").font(.system(size: 9.5)).padding(.horizontal, 6).padding(.vertical, 3).background(mark("estimate"))
            }
        }
    }

    private var inline: some View {
        let parts = rows.map { "\($0.name) \($0.value)" }.joined(separator: "、")
        return Text("**栄養成分表示**（\(panel.basisJapanese)）／\(parts)\(panel.isEstimate ? "（推定値）" : "")")
            .font(.system(size: 10.5))
            .lineSpacing(3)
            .padding(7)
            .background(highlighted.isEmpty ? Color.clear : Color.yellow.opacity(0.45))
    }

    private func mark(_ id: String) -> Color {
        highlighted.contains(id) ? Color.yellow.opacity(0.55) : .clear
    }

    struct Row { var id: String; var name: String; var value: String; var depth: Int }

    var rows: [Row] {
        let p = panel.printed
        func row(_ key: NutrientKey, _ depth: Int) -> Row? {
            p[key].map { Row(id: key.rawValue, name: key.japanese, value: $0 + (key == .energy ? "kcal" : "g"), depth: depth) }
        }
        var rows: [Row] = []
        if let r = row(.energy, 0) { rows.append(r) }
        if panel.groupedZeros.isEmpty {
            [row(.protein, 0), row(.fat, 0)].compactMap { $0 }.forEach { rows.append($0) }
        } else {
            rows.append(Row(id: panel.groupedZeros.map(\.rawValue).joined(separator: " "),
                            name: panel.groupedZeros.map(\.japanese).joined(separator: "・"), value: "0g", depth: 0))
        }
        if let r = row(.saturatedFat, 1) { rows.append(r) }
        if let r = row(.carbohydrate, 0) { rows.append(r) }
        if let r = row(.netCarbs, 1) { rows.append(r) }
        if let r = row(.sugars, p[.netCarbs] != nil ? 2 : 1) { rows.append(r) }
        if let r = row(.fibre, 1) { rows.append(r) }
        if let r = row(.salt, 0) { rows.append(r) }
        return rows
    }
}

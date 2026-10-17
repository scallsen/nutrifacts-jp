import SwiftUI

/// Searchable list of health guidelines. Shared by onboarding and Settings.
struct SourcePicker: View {
    @Binding var selection: String
    @State private var query = ""

    var body: some View {
        let results = ReferenceSource.all.compactMap { source -> (ReferenceSource, String?)? in
            let match = source.matches(query)
            return match.0 ? (source, match.matchedCountry) : nil
        }
        List {
            Section {
                if results.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No guidelines for “\(query)” yet")
                        Text("WHO guidelines apply everywhere.").font(.footnote).foregroundStyle(.secondary)
                    }
                    SourceRow(source: .who, matchedCountry: nil, isSelected: selection == ReferenceSource.who.id) { selection = ReferenceSource.who.id }
                } else {
                    ForEach(results, id: \.0.id) { source, country in
                        SourceRow(source: source, matchedCountry: country, isSelected: selection == source.id) { selection = source.id }
                    }
                }
            } footer: {
                Text(selection == ReferenceSource.who.id
                     ? "No values for energy, protein or carbohydrate."
                     : "Anything missing uses the World Health Organization’s guidelines, marked WHO.")
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Country or organisation")
    }
}

private struct SourceRow: View {
    let source: ReferenceSource
    let matchedCountry: String?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                SourceIcon(source: source)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(source.name).foregroundStyle(.primary)
                        if source.id == ReferenceSource.japan.id { Tag(text: "Suggested", tint: .secondary) }
                    }
                    Text(matchedCountry.map { "Includes \($0)" } ?? source.title)
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(source.detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SourceIcon: View {
    let source: ReferenceSource

    var body: some View {
        Group {
            if let flag = source.flag {
                Text(flag).font(.system(size: 22))
            } else {
                Image(systemName: "globe").font(.system(size: 19, weight: .medium)).foregroundStyle(.white)
            }
        }
        .frame(width: 36, height: 36)
        .background(source.flag == nil ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(.fill.tertiary), in: .rect(cornerRadius: 9))
    }
}

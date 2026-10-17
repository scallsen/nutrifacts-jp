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
            } header: {
                Text("Choose which health authority to determine daily values, percentages and portion size warnings.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .textCase(nil)
                    .padding(.bottom, 4)
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
                        Text(source.name).foregroundStyle(Color.primary)
                        if source.id == ReferenceSource.japan.id { Tag(text: "Suggested", tint: .secondary) }
                    }
                    // Plain colours: inside a Button, hierarchical styles pick up the tint.
                    Text(source.title).font(.footnote).foregroundStyle(Color.secondary)
                    Text(matchedCountry.map { "Includes \($0) · \(source.detail)" } ?? source.detail)
                        .font(.footnote).foregroundStyle(Color.secondary)
                    if source.rule != nil {
                        Text("Displays portion size warnings")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color.blue)
                    }
                }
                Spacer()
                // Always laid out, so selecting a row doesn't reflow its text.
                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
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
                // Circle flags from github.com/HatScripts/circle-flags (MIT).
                Image(flag).resizable().scaledToFit()
            } else {
                Image(systemName: "globe").font(.system(size: 19, weight: .medium)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.blue.gradient)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
    }
}

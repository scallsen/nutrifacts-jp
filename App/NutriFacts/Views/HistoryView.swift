import SwiftUI

/// Previous scans, saved on this iPhone and grouped by day. Rows show the product name when the photo had it.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showJapanese") private var showJapanese = false
    @State private var confirmsClear = false
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if model.history.isEmpty {
                    ContentUnavailableView("No Scans Yet", systemImage: "clock",
                                           description: Text("Labels you scan show up here."))
                } else {
                    let days = Self.days(matching(query))
                    List {
                        if days.isEmpty { ContentUnavailableView.search(text: query) }
                        ForEach(days, id: \.day) { day in
                            Section(Self.title(for: day.day)) {
                                ForEach(day.scans) { scan in
                                    NavigationLink {
                                        ResultView(scan: scan, showsScanAgain: false)
                                    } label: {
                                        row(scan)
                                    }
                                }
                                .onDelete { offsets in model.delete(offsets.map { day.scans[$0].id }) }
                            }
                        }
                        if query.isEmpty {
                            Section {
                                Button("Clear History", role: .destructive) { confirmsClear = true }
                                    .frame(maxWidth: .infinity)
                                    .confirmationDialog("Clear all scans from this iPhone?", isPresented: $confirmsClear, titleVisibility: .visible) {
                                        Button("Clear History", role: .destructive) { model.clearHistory() }
                                    }
                            }
                        }
                    }
                    .searchable(text: $query, prompt: "Search products")
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !model.history.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: HistoryCSV(scans: model.history),
                                  preview: SharePreview("NutriFacts History.csv")) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private func row(_ scan: Scan) -> some View {
        HStack(spacing: 12) {
            LabelThumbnail(panel: scan.panel)
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.title ?? "Unnamed product").lineLimit(2)
                    .foregroundStyle(scan.title == nil ? .secondary : .primary)
                if showJapanese, let printed = scan.printedTitle {
                    Text(printed).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("\(scan.date.formatted(date: .omitted, time: .shortened)) · \(summary(scan.panel))")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func summary(_ panel: LabelPanel) -> String {
        let energy = panel.printed[.energy].map { "\($0) kcal" } ?? "Energy not listed"
        return "\(energy) \(panel.basisDescription)"
    }

    /// Scans whose name, printed name or food type contains the search text.
    private func matching(_ query: String) -> [Scan] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.history }
        return model.history.filter { scan in
            [scan.title, scan.panel.productName?.japanese, scan.box?.category.english, scan.box?.category.japanese]
                .contains { $0?.localizedStandardContains(query) == true }
        }
    }

    /// Scans grouped by the day they were taken, newest day first. History is already newest first.
    static func days(_ scans: [Scan], calendar: Calendar = .current) -> [(day: Date, scans: [Scan])] {
        var days: [(day: Date, scans: [Scan])] = []
        for scan in scans {
            let day = calendar.startOfDay(for: scan.date)
            if days.last?.day == day { days[days.count - 1].scans.append(scan) } else { days.append((day, [scan])) }
        }
        return days
    }

    /// "Today", "Yesterday", "Tuesday, October 14", or with the year when it isn't this year.
    static func title(for day: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: now, toGranularity: .year)
        return day.formatted(sameYear ? .dateTime.weekday(.wide).month(.wide).day() : .dateTime.month(.wide).day().year())
    }
}

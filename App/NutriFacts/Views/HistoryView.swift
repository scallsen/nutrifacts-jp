import SwiftUI

/// Previous scans. A scan doesn't know the product, so rows show the label photo, time and energy.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsClear = false

    var body: some View {
        NavigationStack {
            Group {
                if model.history.isEmpty {
                    ContentUnavailableView("No Scans Yet", systemImage: "clock",
                                           description: Text("Labels you scan show up here."))
                } else {
                    List {
                        ForEach(model.history) { scan in
                            NavigationLink {
                                ResultView(scan: scan, showsScanAgain: false)
                            } label: {
                                HStack(spacing: 12) {
                                    LabelThumbnail(panel: scan.panel)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(summary(scan.panel))
                                        Text(scan.date, format: .dateTime.weekday().hour().minute())
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Section {
                            Button("Clear History", role: .destructive) { confirmsClear = true }
                                .frame(maxWidth: .infinity)
                                .confirmationDialog("Clear all scans from this iPhone?", isPresented: $confirmsClear, titleVisibility: .visible) {
                                    Button("Clear History", role: .destructive) { model.clearHistory() }
                                }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private func summary(_ panel: LabelPanel) -> String {
        let energy = panel.printed[.energy].map { "\($0) kcal" } ?? "Energy not listed"
        return "\(energy) · \(panel.basisDescription)"
    }
}

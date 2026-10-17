import SwiftUI

/// Previous scans. A scan doesn't know the product, so rows show the label photo, time and energy.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.history.isEmpty {
                    ContentUnavailableView("No Scans Yet", systemImage: "clock",
                                           description: Text("Labels you scan show up here."))
                } else {
                    List(model.history) { scan in
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
                                Spacer()
                                GradeBadge(score: PanelAnalysis(panel: scan.panel, basis: .per100, source: .japan).healthScore(), size: 26)
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

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("referenceSource") private var sourceID = ReferenceSource.japan.id
    @AppStorage("showJapanese") private var showJapanese = true

    var body: some View {
        let source = ReferenceSource.with(id: sourceID)
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SourcePicker(selection: $sourceID)
                            .navigationTitle("Health Guidelines")
                    } label: {
                        HStack(spacing: 12) {
                            SourceIcon(source: source)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Health Guidelines")
                                Text(source.name).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text(source.note)
                }
                Section {
                    Toggle("Show Japanese Terms", isOn: $showJapanese)
                } footer: {
                    Text("Shows the Japanese term under each line, to match it to the pack.")
                }
                Section {
                    Button("Clear Scan History", role: .destructive) { model.clearHistory() }
                        .disabled(model.history.isEmpty)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

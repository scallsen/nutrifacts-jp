import FoundationModels
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("referenceSource") private var sourceID = ReferenceSource.japan.id
    @AppStorage("showJapanese") private var showJapanese = false
    @AppStorage(Backend.storageKey) private var backend = Backend.defaultBackend
    @AppStorage("hasOnboarded") private var hasOnboarded = true
    @State private var confirmsClearHistory = false

    var body: some View {
        let source = ReferenceSource.with(id: sourceID)
        NavigationStack {
            Form {
                Section("Results") {
                    NavigationLink {
                        SourcePicker(selection: $sourceID)
                            .navigationTitle("Health Guidelines")
                    } label: {
                        LabeledContent {
                            Text(source.name)
                        } label: {
                            Label("Health Guidelines", systemImage: "heart.text.clipboard")
                        }
                    }
                    Toggle(isOn: $showJapanese) {
                        Label("Show Japanese Terms", systemImage: "character.book.closed")
                    }
                }
                Section("Read Labels With") {
                    Picker("Read Labels With", selection: $backend) {
                        ForEach(Backend.supported) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if backend == .privateCloudCompute, #available(iOS 27, *) {
                    PCCStatusSection()
                }
                if backend == .aiAnd {
                    Section {
                        if AIAndConfig.current.apiURL == nil {
                            Label("Not set up in this build", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        } else {
                            Label("Ready", systemImage: "checkmark.circle").foregroundStyle(.green)
                        }
                    } header: {
                        Text("ai&")
                    } footer: {
                        Text("Photos are sent to the NutriFacts server, which reads them with an AI& model in Japan.")
                    }
                }
                Section {
                    NavigationLink {
                        ActionButtonSetupView()
                    } label: {
                        Label("Action Button", systemImage: "button.horizontal.top.press")
                    }
                }
                Section {
                    Button("Clear Scan History", role: .destructive) { confirmsClearHistory = true }
                        .disabled(model.history.isEmpty)
                        .confirmationDialog("Clear all scans from this iPhone?", isPresented: $confirmsClearHistory, titleVisibility: .visible) {
                            Button("Clear Scan History", role: .destructive) { model.clearHistory() }
                        }
                }
                #if DEBUG
                Section("Debug") {
                    Button("Show Onboarding Again") {
                        close()
                        // Let this sheet finish closing before the root swaps to onboarding.
                        Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            hasOnboarded = false
                        }
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .onAppear { backend = backend.resolved }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.backward", action: close)
                }
            }
        }
    }

    private func close() {
        dismiss()
    }
}

/// Availability and daily quota, as Apple recommends showing them.
@available(iOS 27, *)
private struct PCCStatusSection: View {
    private let model = PrivateCloudComputeLanguageModel()

    var body: some View {
        Section("Private Cloud Compute") {
            switch model.availability {
            case .available:
                if model.quotaUsage.isLimitReached {
                    Label("Today's Limit Reached", systemImage: "xmark.octagon").foregroundStyle(.red)
                } else if case .belowLimit(let info) = model.quotaUsage.status, info.isApproachingLimit {
                    Label("Nearing Today's Limit", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    Label("Available", systemImage: "checkmark.circle").foregroundStyle(.green)
                }
                if let suggestion = model.quotaUsage.limitIncreaseSuggestion {
                    Button("Get More Requests") { suggestion.show() }
                }
            case .unavailable(.deviceNotEligible):
                Label("This iPhone doesn't support Apple Intelligence", systemImage: "iphone.slash")
            case .unavailable:
                Label("Not ready yet. Unavailable in the Simulator.", systemImage: "hourglass")
            }
        }
    }
}

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
                    AIAndSection()
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

/// ai& status and the reasoning level, offered from what the server's model supports.
private struct AIAndSection: View {
    @AppStorage(AIAndConfig.reasoningEffortKey) private var effort = ""
    @State private var server: AIAndReader.ServerConfig?
    @State private var loadFailed = false

    var body: some View {
        Section {
            if AIAndConfig.current.apiURL == nil {
                Label("Not set up in this build", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else if let server {
                Picker(selection: $effort) {
                    // The server's default is listed once, as "Low (Default)", and stored as "" so it
                    // follows the server if its default changes. Without one, the model decides.
                    if server.defaultReasoningEffort == nil {
                        Text("Model Default").tag("")
                    }
                    ForEach(server.reasoningEfforts, id: \.self) { level in
                        if level == server.defaultReasoningEffort {
                            Text("\(Self.name(level)) (Default)").tag("")
                        } else {
                            Text(Self.name(level)).tag(level)
                        }
                    }
                } label: {
                    Label("Reasoning", systemImage: "brain")
                }
            } else if loadFailed {
                Label("Couldn't reach the server", systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
            } else {
                Label { Text("Loading…") } icon: { ProgressView() }
            }
        } header: {
            Text("ai&")
        } footer: {
            Text("Photos are sent to the NutriFacts server, which reads them with an AI& model in Japan. More reasoning can help with hard-to-read labels, but it's slower and costs more.")
        }
        .task {
            guard server == nil, AIAndConfig.current.apiURL != nil else { return }
            do {
                let config = try await AIAndReader.serverConfig()
                server = config
                // A level saved for a previous model may not exist on this one, and picking the
                // default's own level is the same as "Default".
                if !config.reasoningEfforts.contains(effort) || effort == config.defaultReasoningEffort { effort = "" }
            } catch {
                loadFailed = true
            }
        }
    }

    static func name(_ level: String) -> String {
        switch level {
        case "none": "Off"
        case "xhigh": "Extra high"
        default: level.capitalized
        }
    }
}

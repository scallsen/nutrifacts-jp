import FoundationModels
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("referenceSource") private var sourceID = ReferenceSource.japan.id
    @AppStorage("showJapanese") private var showJapanese = true
    @AppStorage(Backend.storageKey) private var backend = Backend.defaultBackend
    @AppStorage(AIAndConfig.urlKey) private var aiAndURL = ""
    @State private var apiKey = Keychain.read(AIAndConfig.keychainAccount) ?? ""

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
                    Picker("Read Labels With", selection: $backend) {
                        ForEach(Backend.supported) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Read Labels With")
                } footer: {
                    Text(Backend.privateCloudCompute.isSupported
                         ? "This only reads the label. NutriFacts works out the score itself, so every option grades the same label the same way."
                         : "This only reads the label; NutriFacts works out the score itself. Private Cloud Compute needs iOS 27. On iOS 26 the on-device model reads the label's text, not the image.")
                }
                if backend == .privateCloudCompute, #available(iOS 27, *) {
                    PCCStatusSection()
                }
                if backend == .aiAnd {
                    Section {
                        TextField("Server URL", text: $aiAndURL)
                            .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("API Key", text: $apiKey)
                            .onSubmit { Keychain.write(apiKey, for: AIAndConfig.keychainAccount) }
                    } header: {
                        Text("ai&")
                    } footer: {
                        Text("Screenshots are sent to this server to be read.")
                    }
                }
                Section {
                    NavigationLink {
                        ActionButtonSetupView()
                    } label: {
                        Label("Set Up the Action Button", systemImage: "button.horizontal.top.press")
                    }
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
            .onAppear { backend = backend.resolved }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        Keychain.write(apiKey, for: AIAndConfig.keychainAccount)
                        dismiss()
                    }
                }
            }
        }
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

import FoundationModels
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Backend.storageKey) private var backend = Backend.defaultBackend
    @AppStorage("dvSource") private var dvSource = DailyValues.shared.defaultSource
    @AppStorage(AIAndConfig.urlKey) private var aiAndURL = ""
    @State private var apiKey = Keychain.read(AIAndConfig.keychainAccount) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Read labels with", selection: $backend) {
                        ForEach(Backend.supported) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Backend")
                } footer: {
                    if Backend.privateCloudCompute.isSupported {
                        Text("The backend only reads the label. Nutrifacts computes the score itself, so every backend grades the same panel the same way.")
                    } else {
                        Text("The backend only reads the label; Nutrifacts computes the score itself. Apple Private Cloud Compute needs iOS 27. On iOS 26 the on-device model reads the label's text, not the image.")
                    }
                }

                if backend == .privateCloudCompute, #available(iOS 27, *) {
                    PCCStatusSection()
                }

                if backend == .aiAnd {
                    Section("ai&") {
                        TextField("Server URL", text: $aiAndURL)
                            .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("API key", text: $apiKey)
                            .onSubmit { Keychain.write(apiKey, for: AIAndConfig.keychainAccount) }
                    }
                }

                Section {
                    Picker("Standard", selection: $dvSource) {
                        ForEach(DailyValues.shared.selectableSourceKeys, id: \.self) { key in
                            Text(DailyValues.shared.sources[key]?.name ?? key).tag(key)
                        }
                    }
                } header: {
                    Text("Daily values")
                } footer: {
                    Text("\(DailyValues.shared.sources[dvSource]?.version.displayName ?? ""). Where it has no value, WHO fills the gap and the row says so.")
                }
            }
            .navigationTitle("Settings")
            .onAppear { backend = backend.resolved }
            .toolbar {
                Button("Done") {
                    Keychain.write(apiKey, for: AIAndConfig.keychainAccount)
                    dismiss()
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
                    Label("Today's limit reached", systemImage: "xmark.octagon").foregroundStyle(.red)
                } else if case .belowLimit(let info) = model.quotaUsage.status, info.isApproachingLimit {
                    Label("Nearing today's limit", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    Label("Available", systemImage: "checkmark.circle").foregroundStyle(.green)
                }
                if let suggestion = model.quotaUsage.limitIncreaseSuggestion {
                    Button("Show options for more requests") { suggestion.show() }
                }
            case .unavailable(.deviceNotEligible):
                Label("This device doesn't support Apple Intelligence", systemImage: "iphone.slash")
            case .unavailable:
                Label("Not ready yet. Unavailable in the Simulator.", systemImage: "hourglass")
            }
        }
    }
}

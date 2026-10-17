import PhotosUI
import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: \Scan.date, order: .reverse) private var scans: [Scan]
    @Environment(\.modelContext) private var context
    @AppStorage(Backend.storageKey) private var backend = Backend.defaultBackend
    @State private var pickedItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var showSettings = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink { ActionButtonSetupView() } label: {
                        Label("Set up the Action Button", systemImage: "button.horizontal.top.press")
                    }
                    let pickerTitle = isScanning ? "Reading label…" : "Score a screenshot"
                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        Label(pickerTitle, systemImage: "text.viewfinder")
                    }
                    .disabled(isScanning)
                } footer: {
                    Text("Reads with \(backend.resolved.title). Change it in Settings.")
                }

                if !scans.isEmpty {
                    Section("History") {
                        ForEach(scans) { scan in
                            NavigationLink(value: scan.persistentModelID) { ScanRow(scan: scan) }
                        }
                        .onDelete { offsets in offsets.forEach { context.delete(scans[$0]) } }
                    }
                }

                Section {
                    ForEach(SampleLabels.all, id: \.name) { sample in
                        NavigationLink {
                            ResultView(title: sample.name, outcome: ScanOutcome(panel: sample.panel), backend: nil)
                        } label: {
                            SampleRow(name: sample.name, panel: sample.panel)
                        }
                    }
                } header: {
                    Text("Sample labels")
                } footer: {
                    Text("Invented products from docs/ui-domain-context.md, one per carb disclosure state.")
                }
            }
            .navigationTitle("Nutrifacts")
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let scan = context.model(for: id) as? Scan {
                    ResultView(title: scan.panel?.productName ?? "Label", outcome: scan.outcome, backend: scan.backend, scan: scan)
                }
            }
            .toolbar {
                Button("Settings", systemImage: "gearshape") { showSettings = true }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task { await scan(item) }
            }
        }
    }

    private func scan(_ item: PhotosPickerItem) async {
        isScanning = true
        defer { isScanning = false; pickedItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let scan = await ScanService.scan(imageData: data, backend: backend.resolved)
        path.append(scan.persistentModelID)
    }
}

private struct ScanRow: View {
    var scan: Scan

    var body: some View {
        HStack(spacing: 12) {
            if let data = scan.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.panel?.productName ?? "Label").lineLimit(1)
                Text("\(scan.date.formatted(date: .abbreviated, time: .shortened)) · \(scan.backend.shortTitle)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if case .scored(_, let score, _) = scan.outcome {
                GradeBadge(score: score, size: 28)
            } else {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
    }
}

private struct SampleRow: View {
    var name: String
    var panel: NutritionPanel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text("\(panel.productName ?? "") · carbs state \(panel.carbState.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if case .scored(_, let score, _) = ScanOutcome(panel: panel) {
                GradeBadge(score: score, size: 28)
            }
        }
    }
}

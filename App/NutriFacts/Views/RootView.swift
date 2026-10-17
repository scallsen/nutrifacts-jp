import SwiftUI

/// The camera fills the screen. A sheet sits over it: small while scanning, half or full height for the result.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        @Bindable var model = model
        CameraBackdrop(target: model.cameraTarget, phase: model.phase, labelFound: model.labelFound)
            .ignoresSafeArea()
            .sheet(isPresented: .constant(hasOnboarded)) {
                SheetContent()
                    .presentationDetents(model.availableDetents, selection: $model.detent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
            .fullScreenCover(isPresented: .constant(!hasOnboarded)) {
                OnboardingView { hasOnboarded = true }
            }
            .onChange(of: hasOnboarded, initial: true) { _, done in
                if done { model.startScanning() }
            }
    }
}

private struct SheetContent: View {
    @Environment(AppModel.self) private var model
    @State private var showsSettings = false
    @State private var showsHistory = false

    var body: some View {
        Group {
            switch model.phase {
            case .scanning:
                ScanningView(onHistory: { showsHistory = true }, onSettings: { showsSettings = true })
            case .result:
                if let scan = model.current {
                    NavigationStack {
                        ResultView(scan: scan)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("History", systemImage: "clock.arrow.circlepath") { showsHistory = true }
                                }
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Settings", systemImage: "gearshape") { showsSettings = true }
                                }
                            }
                    }
                }
            }
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheet(isPresented: $showsHistory) { HistoryView() }
    }
}

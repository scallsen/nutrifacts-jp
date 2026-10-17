import SwiftUI

@main
struct NutriFactsApp: App {
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

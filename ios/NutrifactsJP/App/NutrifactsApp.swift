import SwiftUI

@main
struct NutrifactsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(ScanService.container)
    }
}

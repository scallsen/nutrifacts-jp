import SwiftUI

/// Apps can't capture the screen, so the Action Button runs a two-step Shortcut.
struct ActionButtonSetupView: View {
    var body: some View {
        List {
            Section {
                step(1, "Open **Shortcuts** and tap **+** to make a new shortcut.")
                step(2, "Add the **Take Screenshot** action.")
                step(3, "Add **Score Nutrition Label** (from Nutrifacts). Its Screenshot comes from the previous action automatically.")
                step(4, "Name it, e.g. “Score label”.")
                Link(destination: URL(string: "shortcuts://create-shortcut")!) {
                    Label("Open Shortcuts", systemImage: "square.2.layers.3d")
                }
            } header: {
                Text("1. Make the shortcut")
            }

            Section {
                step(5, "Open **Settings › Action Button**.")
                step(6, "Swipe to **Shortcut** and choose “Score label”.")
            } header: {
                Text("2. Assign it to the Action Button")
            } footer: {
                Text("To scan a pack in a shop, open the Camera app, frame the 栄養成分表示 panel in the viewfinder and press the Action Button. The screenshot of the viewfinder is what gets read, so you don't need to take a photo. It also works with a product page or photo on screen. The grade appears in a few seconds and is saved to your history here.")
            }
        }
        .navigationTitle("Action Button")
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.callout.weight(.bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(.tint, in: .circle)
            Text(text)
        }
    }
}

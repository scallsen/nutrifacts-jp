import SwiftUI

/// The Action Button can open NutriFacts, which starts on the camera.
struct ActionButtonSetupView: View {
    var body: some View {
        List {
            Section {
                step(1, "Open **Settings › Action Button**.")
                step(2, "Swipe to **Shortcut** and tap **Choose a Shortcut**.")
                step(3, "Choose **Open App**, then **NutriFacts**.")
            } header: {
                Text("Open NutriFacts with the Action Button")
            } footer: {
                Text("Press the Action Button, point at the 栄養成分表示 panel and hold still. NutriFacts opens on the camera and takes the photo for you.")
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

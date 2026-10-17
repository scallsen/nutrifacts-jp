import SwiftUI

/// Apps can't capture the screen, so the Action Button runs a two-step Shortcut:
/// Take Screenshot → Score Nutrition Label. A ready-made copy is shared on iCloud.
struct ActionButtonSetupView: View {
    /// The premade "Score Nutrition Label" shortcut. Opening it shows Shortcuts' Add sheet.
    static let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/ed268b6441a3484786386965877c29bb")!

    var body: some View {
        List {
            Section {
                Link(destination: Self.shortcutURL) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.2.layers.3d.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.indigo.gradient, in: .rect(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Shortcut").font(.headline)
                            Text("Score Nutrition Label").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            } header: {
                Text("1. Add the shortcut")
            } footer: {
                Text("Opens Shortcuts. Tap Add Shortcut there.")
            }

            Section {
                step(1, "Open **Settings › Action Button**.")
                step(2, "Swipe to **Shortcut** and choose **Score Nutrition Label**.")
            } header: {
                Text("2. Assign it to the Action Button")
            } footer: {
                Text("To scan a pack in a shop, open the Camera app, frame the 栄養成分表示 panel in the viewfinder and press the Action Button. The screenshot of the viewfinder is what gets read, so you don't need to take a photo. It also works with a product page or photo on screen. The grade appears in a few seconds and is saved to your history here.")
            }

            Section {
                DisclosureGroup("Make it yourself instead") {
                    step(1, "In **Shortcuts**, tap **+**.")
                    step(2, "Add **Take Screenshot**.")
                    step(3, "Add **Score Nutrition Label** (from NutriFacts). Its Screenshot comes from the previous action automatically.")
                    Link(destination: URL(string: "shortcuts://create-shortcut")!) {
                        Label("Open Shortcuts", systemImage: "square.2.layers.3d")
                    }
                }
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

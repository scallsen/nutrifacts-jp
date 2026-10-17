import SwiftUI

/// First launch: a welcome page, then the choice of health guidelines.
struct OnboardingView: View {
    var onFinish: () -> Void
    @AppStorage("referenceSource") private var sourceID = ReferenceSource.japan.id
    @State private var showsGuidelines = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 34) {
                    VStack(spacing: 16) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 84, height: 84)
                            .background(LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 20))
                        Text("Welcome to NutriFacts")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    VStack(alignment: .leading, spacing: 26) {
                        Feature(symbol: "text.viewfinder", tint: .blue, title: "Scan Japanese labels",
                                detail: "Point at the 栄養成分表示 box on the pack.")
                        Feature(symbol: "character.book.closed", tint: .indigo, title: "Read it in English",
                                detail: "Every line translated, with the Japanese alongside.")
                        Feature(symbol: "chart.bar.fill", tint: .orange, title: "See how much is a lot",
                                detail: "Daily % and high or low levels, from guidelines you choose.")
                        Feature(symbol: "lock.fill", tint: .green, title: "Private by design",
                                detail: Backend.privateCloudCompute.isSupported
                                    ? "Labels are read with Apple Intelligence, on your iPhone or Apple’s Private Cloud Compute. Nothing is sent to us."
                                    : "Labels are read with Apple Intelligence on your iPhone. Nothing is sent to us.")
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.horizontal, 24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Label("Scan history is saved only on this iPhone.", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        showsGuidelines = true
                    } label: {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .navigationDestination(isPresented: $showsGuidelines) {
                SourcePicker(selection: $sourceID)
                    .navigationTitle("Health Guidelines")
                    .navigationBarTitleDisplayMode(.large)
                    .safeAreaInset(edge: .bottom) {
                        Button(action: onFinish) {
                            Text("Continue").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    }
            }
        }
    }
}

private struct Feature: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(tint)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

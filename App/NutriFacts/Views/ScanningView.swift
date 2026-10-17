import PhotosUI
import SwiftUI

/// The small sheet shown over the live camera.
struct ScanningView: View {
    @Environment(AppModel.self) private var model
    var onHistory: () -> Void
    var onSettings: () -> Void
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan a Nutrition Label").font(.title2.bold())
                    Text("Point at the nutrition facts box on the back.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                if model.isReading {
                    ProgressView()
                    Text("Reading the label…")
                } else if let error = model.readError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).lineLimit(3)
                } else if model.labelFound {
                    Circle().fill(.yellow).frame(width: 12, height: 12)
                    Text("Found it. Hold still…")
                } else {
                    ProgressView()
                    Text("Looking for the label…")
                }
            }
            .font(.subheadline.weight(.medium))
            .animation(.default, value: model.labelFound)

            PhotosPicker(selection: $pickedItem, matching: .images) {
                Label("Score a Screenshot", systemImage: "photo.on.rectangle")
            }
            .font(.subheadline)
            .disabled(model.isReading)
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                pickedItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    await model.readAndShow(imageData: data)
                }
            }

            HStack {
                Button("History", systemImage: "clock.arrow.circlepath", action: onHistory)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                Spacer()
                Button {
                    Task { await model.capture() }
                } label: {
                    Circle()
                        .strokeBorder(.primary, lineWidth: 4)
                        .overlay(Circle().fill(.primary).padding(7))
                        .frame(width: 66, height: 66)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take Photo")
                Spacer()
                Button("Settings", systemImage: "gearshape", action: onSettings)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

import PhotosUI
import SwiftUI

/// The small sheet shown over the live camera.
struct ScanningView: View {
    @Environment(AppModel.self) private var model
    var onHistory: () -> Void
    var onSettings: () -> Void
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        let forIngredients = model.ingredientsFor != nil
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(forIngredients ? "Scan the Ingredients" : "Scan a Nutrition Label").font(.title2.bold())
                    Text(forIngredients ? "Point at the box listing the ingredients and net contents."
                                        : "Point at the nutrition facts box on the back.").foregroundStyle(.secondary)
                }
                Spacer()
                if forIngredients {
                    Button("Cancel", systemImage: "xmark") { model.cancelIngredientsScan() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                } else {
                    Button("History", systemImage: "clock.arrow.circlepath", action: onHistory)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                }
            }
            HStack(spacing: 8) {
                if model.isReading {
                    ProgressView()
                    Text(forIngredients ? "Reading the ingredients…" : "Reading the label…")
                } else if let error = model.readError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).lineLimit(3)
                } else if model.labelFound {
                    Circle().fill(.yellow).frame(width: 12, height: 12)
                    Text("Found it. Hold still…")
                } else {
                    ProgressView()
                    Text(forIngredients ? "Looking for the ingredients…" : "Looking for the label…")
                }
            }
            .font(.subheadline.weight(.medium))
            .animation(.default, value: model.labelFound)

            Spacer(minLength: 0)

            HStack {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Label("Choose a Screenshot or Photo", systemImage: "photo.on.rectangle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(model.isReading)
                .onChange(of: pickedItem) { _, item in
                    guard let item else { return }
                    pickedItem = nil
                    Task {
                        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                        await model.readAndShow(imageData: data)
                    }
                }
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

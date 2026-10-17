import CoreGraphics
import Foundation
import FoundationModels

/// Reads the label with Apple's Foundation Models, either on Private Cloud Compute or on device.
nonisolated struct AppleIntelligenceReader: LabelReader {
    enum Kind: Sendable { case privateCloudCompute, onDevice }
    var kind: Kind

    func read(_ image: CGImage) async throws -> ExtractedLabel {
        switch kind {
        case .privateCloudCompute:
            guard #available(iOS 27, *) else {
                throw LabelReaderError.modelUnavailable("Private Cloud Compute needs iOS 27")
            }
            return try await readWithPCC(image)
        case .onDevice:
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available: break
            case .unavailable(.deviceNotEligible): throw LabelReaderError.modelUnavailable("this device doesn't support Apple Intelligence")
            case .unavailable(.appleIntelligenceNotEnabled): throw LabelReaderError.modelUnavailable("turn on Apple Intelligence in Settings")
            case .unavailable: throw LabelReaderError.modelUnavailable("the model is still downloading")
            }
            if #available(iOS 27, *), model.capabilities.contains(.vision) {
                return try await respond(model: model, image: image)
            }
            // The model can't take images (iOS 26), so it reads on-device OCR of the photo instead.
            let ocrText = (try? await OCR.text(in: image)) ?? ""
            let session = LanguageModelSession(model: model, instructions: Self.instructions)
            return try await session.respond(generating: ExtractedLabel.self) {
                "Transcribe the Japanese nutrition facts panel from this OCR of a photo (it may contain misreads):"
                ocrText.isEmpty ? "(no text recognised)" : ocrText
            }.content
        }
    }

    @available(iOS 27, *)
    private func readWithPCC(_ image: CGImage) async throws -> ExtractedLabel {
        let model = PrivateCloudComputeLanguageModel()
        switch model.availability {
        case .available: break
        case .unavailable(.deviceNotEligible): throw LabelReaderError.modelUnavailable("this device doesn't support Apple Intelligence")
        case .unavailable: throw LabelReaderError.modelUnavailable("Private Cloud Compute isn't ready yet")
        }
        do {
            return try await respond(model: model, image: image)
        } catch let error as PrivateCloudComputeLanguageModel.Error {
            switch error {
            case .quotaLimitReached(let info):
                throw LabelReaderError.quotaReached(resetDate: info.resetDate)
            case .networkFailure:
                // Apple's guidance: retry on device when the network is unavailable.
                return try await AppleIntelligenceReader(kind: .onDevice).read(image)
            default:
                throw error
            }
        }
    }

    /// iOS 27: the photo alone goes to a model that can see it.
    @available(iOS 27, *)
    private func respond(model: some LanguageModel, image: CGImage) async throws -> ExtractedLabel {
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(generating: ExtractedLabel.self) {
            "Transcribe the Japanese nutrition facts panel in this photo."
            Attachment(image).label("photo")
        }
        return response.content
    }

    static let instructions = """
    You transcribe Japanese nutrition facts panels (栄養成分表示) into structured data. You never judge \
    or score the food, and you never fill in values that aren't printed.

    Rules:
    - Only output lines that are actually printed. A missing line is "not disclosed", never 0.
    - 炭水化物 is carbohydrate (includes fibre). 糖質 is netCarbs. 糖類 is sugars and sits under 糖質 or 炭水化物. \
    食物繊維 is fibre. Never map 糖質 to sugars.
    - 食塩相当量 is salt in grams. ナトリウム is sodium; keep its printed unit (mg, or g when ≥ 1000 mg).
    - エネルギー means energy (熱量). たんぱく, 蛋白質 and タンパク質 mean protein. 飽和脂肪酸 is saturatedFat.
    - Grouped zeros such as たんぱく質・脂質 0g give 0 to each named nutrient.
    - Ranges such as 120〜150kcal: minValue 120, maxValue 150.
    - Convert full-width digits (０-９, ．) to normal numbers. Keep the printed precision.
    - Caffeine, collagen and other items printed outside the panel are nutrient "other".
    - basisText is the per-what phrase, e.g. 1食分（50g）当たり. basisAmount is the grams or ml in it, or 0 if none is printed.
    - If there is no nutrition panel in the image, set panelFound to false and leave lines empty.
    """
}

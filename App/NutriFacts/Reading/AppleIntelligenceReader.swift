import CoreGraphics
import Foundation
import FoundationModels

/// Reads the label with Apple Intelligence: Private Cloud Compute when it can run, otherwise the
/// on-device model. The fallback covers iOS 26, builds without the PCC entitlement, no network,
/// PCC not being ready, and the daily PCC limit.
nonisolated struct AppleIntelligenceReader: LabelReader {
    /// PCC needs iOS 27 and the managed entitlement.
    static var canUsePCC: Bool {
        if #available(iOS 27, *) { return hasPCCEntitlement }
        return false
    }

    /// FoundationModels traps when an app without the entitlement uses PCC, e.g. a build signed with a
    /// personal team. Development builds embed their profile, so check it. App Store builds have none.
    private static let hasPCCEntitlement: Bool = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let profile = String(data: data, encoding: .isoLatin1) else { return true }
        return profile.contains("com.apple.developer.private-cloud-compute")
    }()

    func read(_ image: CGImage) async throws -> LabelReading {
        let clock = ContinuousClock()
        var pccProblem: LabelReaderError?
        var details: [ScanTiming.Detail] = []
        if #available(iOS 27, *), Self.canUsePCC {
            let started = clock.now
            do {
                let label = try await readWithPCC(image)
                return LabelReading(label: label, readBy: .privateCloudCompute,
                                    details: [.init(name: "Model", value: "Private Cloud Compute")])
            } catch let problem as PCCUnavailable {
                pccProblem = problem.error
                details.append(.init(name: "PCC", value: "\(problem.reason) after \(ScanTiming.seconds(clock.now - started)), fell back"))
            }
        } else {
            details.append(.init(name: "PCC", value: Self.canUsePCC ? "needs iOS 27" : "no entitlement in this build"))
        }
        do {
            let started = clock.now
            let label = try await readOnDevice(image)
            details.insert(.init(name: "Model", value: "On device (\(ScanTiming.seconds(clock.now - started)))"), at: 0)
            return LabelReading(label: label, readBy: .onDevice, details: details)
        } catch let error as LabelReaderError {
            // Neither works. If PCC stopped on its daily limit, that's the more useful thing to say.
            if case .quotaReached = pccProblem { throw pccProblem! }
            throw error
        }
    }

    /// PCC can't take this read, but the on-device model might.
    private struct PCCUnavailable: Error {
        var reason: String
        var error: LabelReaderError?
    }

    @available(iOS 27, *)
    private func readWithPCC(_ image: CGImage) async throws -> ExtractedLabel {
        let model = PrivateCloudComputeLanguageModel()
        switch model.availability {
        case .available: break
        case .unavailable(.deviceNotEligible): throw PCCUnavailable(reason: "device not eligible")
        case .unavailable: throw PCCUnavailable(reason: "not ready")
        }
        do {
            return try await respond(model: model, image: image)
        } catch let error as PrivateCloudComputeLanguageModel.Error {
            switch error {
            case .quotaLimitReached(let info):
                throw PCCUnavailable(reason: "daily limit reached", error: .quotaReached(resetDate: info.resetDate))
            case .networkFailure:
                // Apple's guidance: retry on device when the network is unavailable.
                throw PCCUnavailable(reason: "no network")
            case .serviceUnavailable:
                throw PCCUnavailable(reason: "service unavailable")
            default:
                throw error
            }
        }
    }

    private func readOnDevice(_ image: CGImage) async throws -> ExtractedLabel {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available: break
        case .unavailable(.deviceNotEligible): throw LabelReaderError.modelUnavailable("this iPhone doesn't support it, and Private Cloud Compute couldn't be reached")
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
    - basisText is only the per-what phrase, e.g. 1食分（50g）当たり or 1個当たり, without 栄養成分表示 or outer brackets. \
    basisAmount is the grams or ml in it, or 0 if none is printed. Never take basisAmount from 内容量.
    - 内容量 (net contents) is often printed away from the panel. Give its weight or volume and unit if visible, \
    and how many pieces it holds if it says (6個入り). A bare count like 2個 is not a weight.
    - If there is no nutrition panel in the image, set panelFound to false and leave lines empty.
    """
}

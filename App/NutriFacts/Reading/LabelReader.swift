import CoreGraphics
import Foundation
import Vision

/// Where the screenshot is read. The score itself is always computed in the app (docs/health-score.md).
nonisolated enum Backend: String, CaseIterable, Identifiable, Codable, Sendable {
    case privateCloudCompute, onDevice, aiAnd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateCloudCompute: "Apple Private Cloud Compute"
        case .onDevice: "On-device Apple Intelligence"
        case .aiAnd: "ai&"
        }
    }

    var shortTitle: String {
        switch self {
        case .privateCloudCompute: "Apple PCC"
        case .onDevice: "On-device"
        case .aiAnd: "ai&"
        }
    }

    static let storageKey = "backend"

    /// The backend chosen in Settings, falling back when this OS can't run it.
    static var selected: Backend {
        (UserDefaults.standard.string(forKey: storageKey).flatMap(Backend.init(rawValue:)) ?? .defaultBackend).resolved
    }

    /// PCC needs iOS 27. Everything else runs on iOS 26.
    var isSupported: Bool {
        guard self == .privateCloudCompute else { return true }
        if #available(iOS 27, *) { return true }
        return false
    }

    static var supported: [Backend] { allCases.filter(\.isSupported) }

    static var defaultBackend: Backend { Backend.privateCloudCompute.isSupported ? .privateCloudCompute : .onDevice }

    /// A stored choice that this OS can't run (e.g. PCC restored onto iOS 26) falls back to the default.
    var resolved: Backend { isSupported ? self : Self.defaultBackend }
}

protocol LabelReader: Sendable {
    func read(_ image: CGImage, ocrText: String) async throws -> ExtractedLabel
}

nonisolated enum LabelReaderError: LocalizedError {
    case modelUnavailable(String)
    case quotaReached(resetDate: Date?)
    case backendNotConfigured
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let why): "Apple Intelligence isn't available: \(why)."
        case .quotaReached(let date):
            if let date { "You've reached today's Private Cloud Compute limit. It resets \(date.formatted(.relative(presentation: .named)))." }
            else { "You've reached today's Private Cloud Compute limit." }
        case .backendNotConfigured: "Add the ai& server URL and API key in Settings."
        case .badResponse(let code): "The ai& backend returned HTTP \(code)."
        }
    }
}

/// Japanese OCR with Vision. Its text goes to every backend as a hint next to the image,
/// and is the only input when a model can't take images.
nonisolated enum OCR {
    static func text(in image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLanguages = [Locale.Language(identifier: "ja-JP"), Locale.Language(identifier: "en-US")]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // keeps numbers and units as printed
        let observations = try await request.perform(on: image)
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

nonisolated enum LabelReaders {
    static func make(_ backend: Backend) -> any LabelReader {
        switch backend {
        case .privateCloudCompute: AppleIntelligenceReader(kind: .privateCloudCompute)
        case .onDevice: AppleIntelligenceReader(kind: .onDevice)
        case .aiAnd: AIAndReader(config: .current)
        }
    }
}

import CoreGraphics
import Foundation
import Vision

/// Where labels are read, as chosen in Settings. The score is always computed in the app (docs/health-score.md).
nonisolated enum Backend: RawRepresentable, CaseIterable, Identifiable, Hashable, Sendable {
    /// Apple's models: Private Cloud Compute when it can run, the on-device model otherwise.
    case appleIntelligence
    /// AI&, through the NutriFacts API (backend/).
    case aiAnd

    init?(rawValue: String) {
        switch rawValue {
        // Before they were merged, PCC and on-device were separate choices.
        case "appleIntelligence", "privateCloudCompute", "onDevice": self = .appleIntelligence
        case "aiAnd": self = .aiAnd
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .appleIntelligence: "appleIntelligence"
        case .aiAnd: "aiAnd"
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .aiAnd: "ai&"
        }
    }

    static let storageKey = "backend"

    /// The backend chosen in Settings, falling back when this build can't run it.
    static var selected: Backend {
        (UserDefaults.standard.string(forKey: storageKey).flatMap(Backend.init(rawValue:)) ?? .defaultBackend).resolved
    }

    /// ai& needs a NutriFacts API URL in this build. Apple Intelligence always has the on-device model to fall back on.
    var isSupported: Bool {
        switch self {
        case .appleIntelligence: true
        case .aiAnd: AIAndConfig.current.apiURL != nil
        }
    }

    static var supported: [Backend] { allCases.filter(\.isSupported) }

    /// For new users: ai& when this build is set up for it, otherwise Apple Intelligence.
    /// Someone who has already picked a backend in Settings keeps it.
    static var defaultBackend: Backend { Backend.aiAnd.isSupported ? .aiAnd : .appleIntelligence }

    var resolved: Backend { isSupported ? self : Self.defaultBackend }
}

/// Which model actually read a label. Apple Intelligence can end up on either of its two.
nonisolated enum ReadBy: Hashable, Sendable {
    case privateCloudCompute, onDevice, aiAnd
}

nonisolated struct LabelReading: Sendable {
    var label: ExtractedLabel
    var readBy: ReadBy
    /// Backend specifics for ScanTiming, e.g. upload size or why PCC fell back.
    var details: [ScanTiming.Detail] = []
}

protocol LabelReader: Sendable {
    func read(_ image: CGImage) async throws -> LabelReading
}

nonisolated enum LabelReaderError: LocalizedError {
    case modelUnavailable(String)
    case quotaReached(resetDate: Date?)
    case backendNotConfigured
    /// A message from the NutriFacts API, written for the user.
    case aiAnd(String)
    /// The deployed Worker doesn't have this route yet.
    case aiAndRouteMissing

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let why): "Apple Intelligence isn't available: \(why)."
        case .quotaReached(let date):
            if let date { "You've reached today's Private Cloud Compute limit. It resets \(date.formatted(.relative(presentation: .named)))." }
            else { "You've reached today's Private Cloud Compute limit." }
        case .backendNotConfigured: "The ai& server isn't set up in this build. Pick Apple Intelligence in Settings."
        case .aiAnd(let message): message
        case .aiAndRouteMissing: "The ai& server can't read this yet."
        }
    }
}

/// Japanese OCR with Vision, on device. Used only where it's needed: by the on-device model when it
/// can't take images (iOS 26), and by ai&, whose contract includes the text. PCC gets the photo alone.
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
        case .appleIntelligence: AppleIntelligenceReader()
        case .aiAnd: AIAndReader(config: .current)
        }
    }
}

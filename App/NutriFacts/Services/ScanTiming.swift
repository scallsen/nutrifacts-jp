import Foundation
import os

/// Where the time went for one scan. Logged under the "timing" category, and shown on the result in debug builds.
nonisolated struct ScanTiming: Hashable, Codable, Sendable {
    struct Detail: Hashable, Codable, Sendable {
        var name: String
        var value: String
    }

    /// Taking the photo (live camera only).
    var capture: Duration?
    /// Decoding, rotating and scaling the image for the model.
    var prepare: Duration
    /// The backend's whole read, from the app's side: upload, model and download.
    var read: Duration
    /// Waiting for the panel crop for History after the read finished. Usually zero; it runs alongside.
    var cropWait: Duration
    /// Capture to result.
    var total: Duration
    /// Size of the image sent, e.g. "1600×1200".
    var imageSize: String
    /// Backend specifics: which Apple model, upload size, server and AI& time, tokens.
    var details: [Detail]

    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NutriFacts", category: "timing")

    /// One line, for the console.
    var summary: String {
        var parts: [String] = []
        if let capture { parts.append("capture \(Self.seconds(capture))") }
        parts += ["prepare \(Self.seconds(prepare))", "read \(Self.seconds(read))", "crop wait \(Self.seconds(cropWait))",
                  "total \(Self.seconds(total))", "image \(imageSize)"]
        parts += details.map { "\($0.name.lowercased()) \($0.value)" }
        return parts.joined(separator: " · ")
    }

    static func seconds(_ d: Duration) -> String {
        let s = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        return s < 0.1 ? "\(Int((s * 1000).rounded())) ms" : String(format: "%.1f s", s)
    }
}

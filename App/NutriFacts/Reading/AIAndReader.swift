import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Where the NutriFacts API (backend/, a Cloudflare Worker) lives. It holds the AI& key and
/// reads labels with AI&; the app never sees the key. Set in App/Config/NutriFacts.xcconfig.
nonisolated struct AIAndConfig: Sendable {
    var apiURL: URL?
    /// Optional shared token the Worker can require (X-App-Token). From the git-ignored Secrets.xcconfig.
    var appToken: String?
    /// Reasoning level picked in Settings. Nil uses the Worker's default (AIAND_REASONING_EFFORT).
    var reasoningEffort: String?

    static let reasoningEffortKey = "aiAndReasoningEffort"

    static var current: AIAndConfig {
        let info = Bundle.main.infoDictionary ?? [:]
        let url = (info["NutriFactsAPIURL"] as? String).flatMap(URL.init(string:))
        let token = info["NutriFactsAppToken"] as? String
        // The placeholder URL in the committed xcconfig means "not set up in this build".
        let effort = UserDefaults.standard.string(forKey: reasoningEffortKey)
        return AIAndConfig(apiURL: url?.absoluteString.localizedCaseInsensitiveContains("YOUR-SUBDOMAIN") == true ? nil : url,
                           appToken: token?.isEmpty == false ? token : nil,
                           reasoningEffort: effort?.isEmpty == false ? effort : nil)
    }
}

/// Reads the label through the NutriFacts API, which asks a vision model on AI&.
/// Contract: docs/aiand.md. The answer has the same shape as the Apple models' `ExtractedLabel`.
nonisolated struct AIAndReader: LabelReader {
    var config: AIAndConfig
    var session: URLSession = .shared

    private struct Body: Encodable {
        var image: String
        var mimeType = "image/jpeg"
        var reasoningEffort: String?
    }

    /// What the Worker's model offers, for the Reasoning picker in Settings.
    struct ServerConfig: Decodable, Sendable {
        var model: String
        var reasoningEfforts: [String]
        var defaultReasoningEffort: String?
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { var message: String? }
        var error: Detail?
    }

    func read(_ image: CGImage) async throws -> LabelReading {
        guard let apiURL = config.apiURL else { throw LabelReaderError.backendNotConfigured }
        var request = URLRequest(url: apiURL.appending(path: "v1/nutrition-label/read"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = config.appToken { request.setValue(token, forHTTPHeaderField: "X-App-Token") }
        let clock = ContinuousClock()
        let encodeStarted = clock.now
        // The app already scaled the image (AppModel.readMaxSide); this only guards other callers.
        let jpeg = Self.jpeg(Self.downscaled(image, maxSide: 2048))
        request.httpBody = try JSONEncoder().encode(Body(image: jpeg.base64EncodedString(), reasoningEffort: config.reasoningEffort))
        let encode = clock.now - encodeStarted

        let sendStarted = clock.now
        let (data, response) = try await session.data(for: request)
        let roundTrip = clock.now - sendStarted
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message
            throw LabelReaderError.aiAnd(message ?? "The ai& server returned HTTP \(status).")
        }
        let details = Self.details(response: response as? HTTPURLResponse, encode: encode, jpegBytes: jpeg.count,
                                   bodyBytes: request.httpBody?.count ?? 0, roundTrip: roundTrip)
        return LabelReading(label: try JSONDecoder().decode(ExtractedLabel.self, from: data), readBy: .aiAnd, details: details)
    }

    /// Splits the round trip into the Worker's time (and AI&'s within it) and the rest: network, TLS and queueing.
    static func details(response: HTTPURLResponse?, encode: Duration, jpegBytes: Int, bodyBytes: Int, roundTrip: Duration) -> [ScanTiming.Detail] {
        var details = [ScanTiming.Detail(name: "Upload", value: "\(bodyBytes / 1024) KB (JPEG \(jpegBytes / 1024) KB)"),
                       ScanTiming.Detail(name: "Encode", value: ScanTiming.seconds(encode)),
                       ScanTiming.Detail(name: "Round trip", value: ScanTiming.seconds(roundTrip))]
        // Server-Timing: aiand;dur=5012, total;dur=5100 (milliseconds)
        var ms: [String: Int] = [:]
        for part in (response?.value(forHTTPHeaderField: "Server-Timing") ?? "").split(separator: ",") {
            let fields = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            if let name = fields.first, let dur = fields.first(where: { $0.hasPrefix("dur=") }).flatMap({ Int($0.dropFirst(4)) }) {
                ms[name] = dur
            }
        }
        if let total = ms["total"] {
            details.append(.init(name: "Server", value: ScanTiming.seconds(.milliseconds(total))
                                 + (ms["aiand"].map { " (AI& \(ScanTiming.seconds(.milliseconds($0))))" } ?? "")))
            details.append(.init(name: "Network", value: ScanTiming.seconds(roundTrip - .milliseconds(total))))
        }
        if let usage = response?.value(forHTTPHeaderField: "X-AIAnd-Usage"), !usage.isEmpty {
            details.append(.init(name: "Tokens", value: usage))
        }
        if let effort = response?.value(forHTTPHeaderField: "X-Reasoning-Effort") {
            details.append(.init(name: "Reasoning", value: effort))
        }
        return details
    }

    static func serverConfig(_ config: AIAndConfig = .current, session: URLSession = .shared) async throws -> ServerConfig {
        guard let apiURL = config.apiURL else { throw LabelReaderError.backendNotConfigured }
        var request = URLRequest(url: apiURL.appending(path: "v1/config"))
        request.timeoutInterval = 15
        if let token = config.appToken { request.setValue(token, forHTTPHeaderField: "X-App-Token") }
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(ServerConfig.self, from: data)
    }

    // MARK: Image

    static func jpeg(_ image: CGImage, quality: Double = 0.8) -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    /// Keeps the upload small; labels stay legible at 2048 px.
    static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let scale = Double(maxSide) / Double(longest)
        let w = Int(Double(image.width) * scale), h = Int(Double(image.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}

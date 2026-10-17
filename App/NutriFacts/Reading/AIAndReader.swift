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

    static var current: AIAndConfig {
        let info = Bundle.main.infoDictionary ?? [:]
        let url = (info["NutriFactsAPIURL"] as? String).flatMap(URL.init(string:))
        let token = info["NutriFactsAppToken"] as? String
        // The placeholder URL in the committed xcconfig means "not set up in this build".
        return AIAndConfig(apiURL: url?.absoluteString.localizedCaseInsensitiveContains("YOUR-SUBDOMAIN") == true ? nil : url,
                           appToken: token?.isEmpty == false ? token : nil)
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
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { var message: String? }
        var error: Detail?
    }

    func read(_ image: CGImage) async throws -> ExtractedLabel {
        guard let apiURL = config.apiURL else { throw LabelReaderError.backendNotConfigured }
        var request = URLRequest(url: apiURL.appending(path: "v1/nutrition-label/read"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = config.appToken { request.setValue(token, forHTTPHeaderField: "X-App-Token") }
        let jpeg = Self.jpeg(Self.downscaled(image, maxSide: 2048))
        request.httpBody = try JSONEncoder().encode(Body(image: jpeg.base64EncodedString()))

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message
            throw LabelReaderError.aiAnd(message ?? "The ai& server returned HTTP \(status).")
        }
        return try JSONDecoder().decode(ExtractedLabel.self, from: data)
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

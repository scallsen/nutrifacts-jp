import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Settings for the ai& backend. The URL lives in UserDefaults, the API key in the Keychain.
nonisolated struct AIAndConfig: Sendable {
    var baseURL: URL?
    var apiKey: String?

    static let urlKey = "aiAndBaseURL"
    static let keychainAccount = "aiAndAPIKey"

    static var current: AIAndConfig {
        AIAndConfig(baseURL: UserDefaults.standard.string(forKey: urlKey).flatMap(URL.init(string:)),
                    apiKey: Keychain.read(keychainAccount))
    }
}

/// Reads the label through the ai& backend. Contract: docs/backend-api.md.
nonisolated struct AIAndReader: LabelReader {
    var config: AIAndConfig
    var session: URLSession = .shared

    struct RequestBody: Encodable {
        var image: String        // base64 JPEG
        var mimeType = "image/jpeg"
        var ocrText: String
        var locale = "ja-JP"
        var schemaVersion = 1
    }

    func read(_ image: CGImage, ocrText: String) async throws -> ExtractedLabel {
        guard let base = config.baseURL, let key = config.apiKey, !key.isEmpty else {
            throw LabelReaderError.backendNotConfigured
        }
        var request = URLRequest(url: base.appending(path: "v1/nutrition-label/read"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RequestBody(image: Self.jpeg(image).base64EncodedString(), ocrText: ocrText))

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw LabelReaderError.badResponse(status) }
        return try JSONDecoder().decode(ExtractedLabel.self, from: data)
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.8) -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }
}

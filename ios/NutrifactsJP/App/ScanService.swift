import CoreGraphics
import Foundation
import ImageIO
import SwiftData

/// Screenshot in, saved `Scan` out. Shared by the app UI and the App Intent.
enum ScanService {
    static let container: ModelContainer = {
        do { return try ModelContainer(for: Scan.self) }
        catch { fatalError("Couldn't open the scan store: \(error)") }
    }()

    static var selectedBackend: Backend {
        (UserDefaults.standard.string(forKey: Backend.storageKey).flatMap(Backend.init(rawValue:)) ?? .defaultBackend).resolved
    }

    enum ImageError: LocalizedError {
        case unreadable
        var errorDescription: String? { "That file isn't an image Nutrifacts can read." }
    }

    @discardableResult
    static func scan(imageData: Data, backend: Backend = selectedBackend) async -> Scan {
        let backend = backend.resolved
        let scan: Scan
        do {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImageError.unreadable }
            let ocr = (try? await OCR.text(in: image)) ?? ""
            let label = try await LabelReaders.make(backend).read(image, ocrText: ocr)
            scan = Scan(backend: backend, thumbnail: thumbnail(from: source), label: label)
        } catch {
            scan = Scan(backend: backend, thumbnail: nil, label: nil, errorMessage: error.localizedDescription)
        }
        container.mainContext.insert(scan)
        try? container.mainContext.save()
        return scan
    }

    private static func thumbnail(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 600,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return AIAndReader.jpeg(thumb, quality: 0.7)
    }
}

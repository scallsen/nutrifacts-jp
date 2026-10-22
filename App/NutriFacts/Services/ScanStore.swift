import Foundation
import os

/// Scans saved on this iPhone, so History survives a relaunch. Each scan is a folder in Application Support
/// named by its ID: scan.json, with the label and ingredients photos beside it as JPEGs so the JSON stays small.
/// Debug builds also keep frame.jpg, the whole photo the model read, for `export()`.
/// Nothing here leaves the device.
struct ScanStore {
    let folder: URL

    static let shared = ScanStore(folder: .applicationSupportDirectory.appending(path: "Scans", directoryHint: .isDirectory))

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NutriFacts", category: "store")
    private static let scanFile = "scan.json", labelPhoto = "label.jpg", boxPhoto = "box.jpg", framePhoto = "frame.jpg"

    /// Every saved scan, newest first. A folder that can't be read is skipped and logged, never deleted.
    func load() -> [Scan] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        let scans = folders.compactMap { dir -> Scan? in
            do {
                var scan = try decoder.decode(Scan.self, from: Data(contentsOf: dir.appending(path: Self.scanFile)))
                scan.panel.photo = try? Data(contentsOf: dir.appending(path: Self.labelPhoto))
                scan.boxPhoto = try? Data(contentsOf: dir.appending(path: Self.boxPhoto))
                scan.framePhoto = try? Data(contentsOf: dir.appending(path: Self.framePhoto))
                return scan
            } catch {
                Self.logger.error("couldn't read saved scan \(dir.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return scans.sorted { $0.date > $1.date }
    }

    /// Writes a scan, replacing what was saved for it. Photos don't change once taken, so they're written once.
    func save(_ scan: Scan) {
        let dir = folder.appending(path: scan.id.uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var stripped = scan
            stripped.panel.photo = nil
            stripped.boxPhoto = nil
            stripped.framePhoto = nil
            try JSONEncoder().encode(stripped).write(to: dir.appending(path: Self.scanFile), options: .atomic)
            for (name, data) in [(Self.labelPhoto, scan.panel.photo), (Self.boxPhoto, scan.boxPhoto), (Self.framePhoto, scan.framePhoto)] {
                let url = dir.appending(path: name)
                if let data, !FileManager.default.fileExists(atPath: url.path()) { try data.write(to: url, options: .atomic) }
            }
        } catch {
            Self.logger.error("couldn't save scan \(scan.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete(_ id: Scan.ID) {
        try? FileManager.default.removeItem(at: folder.appending(path: id.uuidString, directoryHint: .isDirectory))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Every saved scan as one zip, for `npm run eval:import` on a Mac (backend/eval/README.md).
    /// The zip is made by the system (NSFileCoordinator's forUploading), then copied out before it's removed.
    func export() throws -> URL {
        let out = FileManager.default.temporaryDirectory.appending(path: "NutriFacts Scans.zip")
        try? FileManager.default.removeItem(at: out)
        var coordinatorError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { zip in
            do { try FileManager.default.copyItem(at: zip, to: out) } catch { copyError = error }
        }
        if let error = coordinatorError ?? copyError { throw error }
        return out
    }
}

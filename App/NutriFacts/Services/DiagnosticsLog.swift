import CoreTransferable
import Foundation
import OSLog
import UIKit
import UniformTypeIdentifiers

/// The text file behind Settings › Share Logs: device and settings, each scan's timing, and this
/// session's log lines from the app (timing, errors). No photos or label contents.
struct DiagnosticsLog: Transferable {
    /// Scans in memory this session, newest first.
    var history: [Scan]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { log in
            let url = FileManager.default.temporaryDirectory
                .appending(path: "NutriFacts logs \(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))).txt")
            try await log.text().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    @MainActor
    func text() async -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let defaults = UserDefaults.standard
        var lines = [
            "NutriFacts \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))",
            "\(UIDevice.current.model) \(Self.hardwareModel), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "Exported \(Date.now.formatted(date: .abbreviated, time: .standard))",
            "",
            "Settings",
            "  Read labels with: \(Backend.selected.title)",
            "  Private Cloud Compute usable: \(AppleIntelligenceReader.canUsePCC ? "yes" : "no")",
            "  ai& server: \(AIAndConfig.current.apiURL?.absoluteString ?? "not set up")",
            "  ai& reasoning: \(defaults.string(forKey: AIAndConfig.reasoningEffortKey).flatMap { $0.isEmpty ? nil : $0 } ?? "server default")",
            "  Image sent: whole frame, up to \(AppModel.readMaxSide) px",
            "",
            "Scans this session (newest first)",
        ]
        let real = history.filter { $0.timing != nil }
        if real.isEmpty { lines.append("  none") }
        for scan in real {
            let by = switch scan.readBy {
            case .privateCloudCompute: "PCC"
            case .onDevice: "on device"
            case .aiAnd: "ai&"
            case nil: "?"
            }
            lines.append("  \(scan.date.formatted(date: .omitted, time: .standard)) · \(by) · \(scan.timing!.summary)")
        }
        lines += ["", "Log (this session)"]
        lines += await Task.detached { Self.logEntries() }.value
        return lines.joined(separator: "\n") + "\n"
    }

    /// This process's log lines from the app's own subsystem.
    nonisolated private static func logEntries() -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return ["  (log unavailable)"] }
        let subsystem = Bundle.main.bundleIdentifier ?? "NutriFacts"
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        guard let entries = try? store.getEntries(matching: predicate) else { return ["  (log unavailable)"] }
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.map { entry in
            let level = switch entry.level {
            case .error, .fault: "ERROR"
            default: "info"
            }
            return "  \(entry.date.formatted(date: .omitted, time: .standard)) [\(entry.category)] \(level): \(entry.composedMessage)"
        }
        return lines.isEmpty ? ["  none"] : lines
    }

    /// e.g. "iPhone18,1". UIDevice only says "iPhone".
    private static var hardwareModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

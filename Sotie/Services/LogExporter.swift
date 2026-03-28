//
//  LogExporter.swift
//  Sotie
//
//  Exports recent os.Logger entries so users can share them with the developer.
//
//

import Foundation
import OSLog

/// Collects and exports recent log entries from the unified logging system.
/// Intentionally nonisolated — log collection may be called from background threads.
nonisolated enum LogExporter {

  /// Gather Sotie logs from the current app session.
  /// Note: OSLogStore(scope: .currentProcessIdentifier) only retains
  /// in-memory logs. Debug/info entries may not survive app restarts.
  static func exportRecentLogs(hours: Int = 24) -> String {
    do {
      let store = try OSLogStore(scope: .currentProcessIdentifier)
      let cutoff = store.position(date: Date().addingTimeInterval(-Double(hours) * 3600))

      let entries = try store.getEntries(at: cutoff)
        .compactMap { $0 as? OSLogEntryLog }
        .filter { $0.subsystem == (Bundle.main.bundleIdentifier ?? "com.sotie.journal") }

      guard !entries.isEmpty else {
        return "No logs found in the current session."
      }

      let timeFmt = Foundation.DateFormatter()
      timeFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

      var output = "Logs (\(entries.count)):\n"

      for entry in entries {
        let time = timeFmt.string(from: entry.date)
        let level = levelLabel(entry.level)
        output += "[\(time)] [\(level)] [\(entry.category)] \(entry.composedMessage)\n"
      }

      return output

    } catch {
      return "Failed to export logs: \(error.localizedDescription)"
    }
  }

  /// Create a temporary file with logs and return its URL for sharing.
  static func exportLogsToFile(hours: Int = 24) -> URL? {
    let content = exportRecentLogs(hours: hours)

    let dateFormatter = Foundation.DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
    let filename = "sotie_logs_\(dateFormatter.string(from: Date())).txt"

    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

    do {
      try content.write(to: tempURL, atomically: true, encoding: .utf8)
      return tempURL
    } catch {
      AppLogger.app.error("Failed to write log file: \(error)")
      return nil
    }
  }

  // MARK: - Helpers

  private static func levelLabel(_ level: OSLogEntryLog.Level) -> String {
    switch level {
    case .debug: return "DEBUG"
    case .info: return "INFO"
    case .notice: return "NOTICE"
    case .error: return "ERROR"
    case .fault: return "FAULT"
    default: return "UNKNOWN"
    }
  }
}

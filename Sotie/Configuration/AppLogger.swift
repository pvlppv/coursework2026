import Foundation
import os

/// Centralized loggers for Sotie.
/// Logs stay on-device. Users can share them via
/// Settings → Privacy → Analytics & Improvements → Analytics Data.
///
/// All properties are `nonisolated` computed vars returning `os.Logger` (a `Sendable` value type).
/// This avoids global-actor inference entirely — safe to call from any isolation domain.
enum AppLogger {

  /// Data layer: SwiftData, JSON decode, persistence, drafts
  nonisolated static var data: Logger {
    Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sotie.journal", category: "Data")
  }

  /// AI service: streaming, summarisation, quota, prompts
  nonisolated static var ai: Logger {
    Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sotie.journal", category: "AI")
  }

  /// App lifecycle: launch, migration, recovery, navigation
  nonisolated static var app: Logger {
    Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sotie.journal", category: "App")
  }

  /// Notifications: scheduling, follow-ups, re-engagement
  nonisolated static var notifications: Logger {
    Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sotie.journal", category: "Notifications")
  }

  /// Premium / StoreKit: purchases, entitlements, debug resets
  nonisolated static var premium: Logger {
    Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sotie.journal", category: "Premium")
  }
}

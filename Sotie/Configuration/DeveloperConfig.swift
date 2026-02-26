import Foundation
import os

// Note: AIQuotaManager import is implicit through module

/// Development configuration flags
struct DeveloperConfig {

  /// Set to true when Apple Developer account is available
  /// This enables CloudKit sync, push notifications, and other features requiring paid account
  static let hasAppleDeveloperAccount = false

  /// Dynamic bundle ID — reads from project settings, no hardcoding needed.
  /// Changes automatically when you change PRODUCT_BUNDLE_IDENTIFIER in Xcode.
  nonisolated static let appBundleID = Bundle.main.bundleIdentifier ?? "com.sotie.journal"

  /// CloudKit container identifier (used when developer account is available)
  static let cloudKitContainerID = "iCloud.\(appBundleID)"

  /// Features available only with Apple Developer account
  struct Features {
    static let cloudKitSync = false
    static let pushNotifications = false
    static let backgroundSync = false
    static let iCloudBackup = false
  }

  /// AI Features - Set to false to completely disable all AI functionality
  struct AI {
    static let enabled = true
  }

  /// Premium/StoreKit Features
  struct Premium {
    /// Premium access must come from StoreKit, backend entitlement, or explicit UI-test launch arguments.
    static let debugPremiumEnabled = false

    /// StoreKit transaction verification should not be bypassed in app runtime.
    static let skipVerification = false
  }

  /// Developer tools for debugging and testing
  struct Debug {
    /// Reset AI daily limit (for testing only)
    /// Resets both question count (200/day for all) and entry ID (free users only)
    static func resetAIDailyLimit() {
      #if DEBUG
        AIQuotaManager.shared.resetDailyLimit()
        AppLogger.app.info("AI daily limit reset - you can now make requests again")
        AppLogger.app.info("Question count: reset to 0 (200 questions available)")
        AppLogger.app.info("Free users: Entry ID cleared, can pick new entry")
      #endif
    }

    /// Reset premium data (for testing only)
    static func resetPremiumData() {
      #if DEBUG
        PremiumManager.shared.resetAllData()
        AppLogger.app.info("Premium data reset")
      #endif
    }
  }
}

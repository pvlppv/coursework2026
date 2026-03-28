import Foundation
import os

/// Client-side quota & rate-limit manager for AI services.
/// Handles daily question caps, per-entry locks (free tier), and burst throttling.
/// Content safety is enforced by backend-owned AI prompts and by
/// the LLM provider's own safety filters — this class does NOT inspect
/// prompt or response content.
/// Delegates to PremiumManager for all persistent tracking.
final class AIQuotaManager: Sendable {

  nonisolated static let shared = AIQuotaManager()

  private init() {
    // No initialization needed - all tracking handled by PremiumManager
  }

  // MARK: - Question Limit Checks

  /// Check if user can ask an AI response (delegates to PremiumManager)
  /// - Parameter entryId: The entry ID where AI will be used (for free user tracking)
  nonisolated func canRequestAIResponse(forEntryId entryId: String? = nil) async -> Bool {
    await MainActor.run {
      PremiumManager.shared.canRequestAIResponse(forEntryId: entryId)
    }
  }

  /// Record an AI response for premium users (delegates to PremiumManager)
  nonisolated func recordAIResponse() async {
    await MainActor.run {
      PremiumManager.shared.recordAIResponse()
    }
  }

  /// Reserve an outbound AI request slot, applying burst protection.\n  /// Throws if per-minute or daily cap is exceeded.
  nonisolated func reserveRequestSlot() async throws {
    try await MainActor.run {
      try PremiumManager.shared.reserveRequestSlot()
    }
  }

  /// Get current usage statistics (delegates to PremiumManager)
  nonisolated func getUsageStats() async -> AIResponseUsageStats {
    await MainActor.run {
      PremiumManager.shared.getAIResponseUsageStats()
    }
  }

  // MARK: - Reset (for testing/admin)

  #if DEBUG
    /// Reset all usage data (delegates to PremiumManager)
    nonisolated func resetAllData() {
      Task { @MainActor in
        PremiumManager.shared.resetDailyResponses()
      }

      AppLogger.ai.info("All quota data reset")
    }

    /// Reset daily limit for developer testing
    nonisolated func resetDailyLimit() {
      Task { @MainActor in
        PremiumManager.shared.resetDailyResponses()
      }

      AppLogger.ai.info("Daily response limit reset for testing")
    }
  #endif
}

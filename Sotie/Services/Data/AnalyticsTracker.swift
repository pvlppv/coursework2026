import Combine
import Foundation
import os
import SwiftData

@MainActor
final class AnalyticsTracker: ObservableObject {
  static let shared = AnalyticsTracker()

  @Published private(set) var analyticsData: AnalyticsData?

  private var modelContext: ModelContext?
  private var sessionStartTime: Date?
  private var isSessionActive = false
  private var accumulatedSeconds: TimeInterval = 0  // Time accumulated before pauses

  // UserDefaults keys for session persistence
  private let sessionStartKey = "analytics.sessionStart"
  private let sessionActiveKey = "analytics.sessionActive"
  private let accumulatedKey = "analytics.accumulatedSeconds"
  private let sessionPausedKey = "analytics.sessionPaused"

  // Maximum reasonable session duration (2 hours)
  private let maxSessionDuration: TimeInterval = 2 * 60 * 60

  private init() {
    // Check for orphaned sessions on init
    recoverOrphanedSession()
  }

  // MARK: - Initialization

  func initialize(with modelContext: ModelContext) {
    self.modelContext = modelContext
    loadOrCreateAnalyticsData()
  }

  private func loadOrCreateAnalyticsData() {
    guard let context = modelContext else { return }

    let descriptor = FetchDescriptor<AnalyticsData>()

    do {
      let results = try context.fetch(descriptor)

      if results.count > 1 {
        // Multiple rows detected (import or race condition) — merge into one canonical row
        let primary = results[0]
        if let mergedAnalytics = StatisticsCalculator.mergedAnalytics(from: results) {
          primary.totalSecondsSpent = mergedAnalytics.totalSecondsSpent
          primary.totalAIResponsesGenerated = mergedAnalytics.totalAIResponsesGenerated
          primary.totalUserResponses = mergedAnalytics.totalUserResponses
          primary.totalConversations = mergedAnalytics.totalConversations
          primary.lastUpdated = Date()
        }
        for record in results where record.id != primary.id {
          context.delete(record)
        }
        try context.save()
        analyticsData = primary
        AppLogger.data.warning("Cleaned up \(results.count - 1) duplicate AnalyticsData records")
      } else if let existing = results.first {
        analyticsData = existing
      } else {
        // Create new analytics data
        let newData = AnalyticsData()
        context.insert(newData)
        try context.save()
        analyticsData = newData
      }
    } catch {
      AppLogger.data.error("Failed to load analytics data: \(error)")
      // Create fallback in-memory data
      analyticsData = AnalyticsData()
    }
  }

  // MARK: - Session Recovery

  private func recoverOrphanedSession() {
    let defaults = UserDefaults.standard

    guard defaults.bool(forKey: sessionActiveKey),
      let startTimestamp = defaults.object(forKey: sessionStartKey) as? Date
    else {
      // No orphaned session
      return
    }

    // Read accumulated BEFORE clearing
    let accumulated = defaults.double(forKey: accumulatedKey)
    let wasPaused = defaults.bool(forKey: sessionPausedKey)
    let totalDuration = Self.recoveredDuration(
      startTimestamp: wasPaused ? nil : startTimestamp,
      accumulated: accumulated,
      now: Date()
    )
    let activeDuration = max(0, totalDuration - accumulated)

    // Clear immediately to prevent double-counting
    clearPersistedSession()

    AppLogger.data.info("Found orphaned session. Active: \(Int(activeDuration))s, Accumulated: \(Int(accumulated))s")

    // Cap at maxSessionDuration and require at least 1 second
    let capped = min(totalDuration, maxSessionDuration)
    guard capped >= 1 else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self = self else { return }
      self.analyticsData?.addTimeSpent(seconds: capped)
      self.saveAnalyticsData()

      AppLogger.data.info("Recovered orphaned session: \(Int(capped))s")
    }
  }

  // MARK: - Session Tracking

  func startEntrySession() {
    guard !isSessionActive else { return }

    let now = Date()
    sessionStartTime = now
    accumulatedSeconds = 0
    isSessionActive = true

    // Persist session start to handle crashes
    persistSession(startTime: now, accumulated: 0, isPaused: false)

    AppLogger.data.info("Started entry session at \(now)")
  }

  func endEntrySession() {
    guard isSessionActive else { return }

    // Calculate total: accumulated (from pause/resume cycles) + current active segment
    let currentSegment: TimeInterval
    if let startTime = sessionStartTime {
      currentSegment = Date().timeIntervalSince(startTime)
    } else {
      // Session was paused — no active segment
      currentSegment = 0
    }
    let totalDuration = accumulatedSeconds + currentSegment

    // Only record sessions longer than 1 second to filter out accidental opens
    guard totalDuration >= 1 else {
      resetSession()
      return
    }

    // Cap at max duration to prevent unreasonable values
    let capped = min(totalDuration, maxSessionDuration)

    AppLogger.data.info("Ended entry session. Duration: \(Int(capped))s (accumulated: \(Int(self.accumulatedSeconds))s + active: \(Int(currentSegment))s)")

    // Add time to analytics
    analyticsData?.addTimeSpent(seconds: capped)
    saveAnalyticsData()

    resetSession()
  }

  /// Call when app goes to background — pauses the timer
  func pauseSession() {
    guard isSessionActive, let startTime = sessionStartTime else { return }

    let currentSegment = Date().timeIntervalSince(startTime)
    accumulatedSeconds += currentSegment
    sessionStartTime = nil  // Pause — no active start time

    // Persist accumulated time for crash safety
    persistSession(startTime: startTime, accumulated: accumulatedSeconds, isPaused: true)

    AppLogger.data.info("Paused session. Accumulated: \(Int(self.accumulatedSeconds))s")
  }

  /// Call when app returns to foreground — resumes the timer
  func resumeSession() {
    guard isSessionActive, sessionStartTime == nil else { return }

    let resumedAt = Date()
    sessionStartTime = resumedAt  // Start new active segment

    // Update persisted start time
    persistSession(startTime: resumedAt, accumulated: accumulatedSeconds, isPaused: false)

    AppLogger.data.info("Resumed session. Accumulated so far: \(Int(self.accumulatedSeconds))s")
  }

  private func persistSession(startTime: Date, accumulated: TimeInterval, isPaused: Bool) {
    let defaults = UserDefaults.standard
    defaults.set(startTime, forKey: sessionStartKey)
    defaults.set(true, forKey: sessionActiveKey)
    defaults.set(accumulated, forKey: accumulatedKey)
    defaults.set(isPaused, forKey: sessionPausedKey)
  }

  private func resetSession() {
    sessionStartTime = nil
    accumulatedSeconds = 0
    isSessionActive = false
    clearPersistedSession()
  }

  private func clearPersistedSession() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: sessionStartKey)
    defaults.set(false, forKey: sessionActiveKey)
    defaults.removeObject(forKey: accumulatedKey)
    defaults.removeObject(forKey: sessionPausedKey)
  }

  static func recoveredDuration(
    startTimestamp: Date?,
    accumulated: TimeInterval,
    now: Date
  ) -> TimeInterval {
    let activeDuration: TimeInterval
    if let startTimestamp {
      activeDuration = max(0, now.timeIntervalSince(startTimestamp))
    } else {
      activeDuration = 0
    }

    return accumulated + activeDuration
  }

  // MARK: - AI Conversation Tracking

  func recordAIResponse() {
    analyticsData?.recordAIResponse()
    saveAnalyticsData()

    AppLogger.data.info("Recorded AI response. Total: \(self.analyticsData?.totalAIResponsesGenerated ?? 0)")
  }

  func recordUserResponse() {
    analyticsData?.recordUserResponse()
    saveAnalyticsData()

    AppLogger.data.info("Recorded user response. Total: \(self.analyticsData?.totalUserResponses ?? 0)")
  }

  func recordConversation() {
    analyticsData?.recordConversation()
    saveAnalyticsData()

    AppLogger.data.info("Recorded conversation. Total: \(self.analyticsData?.totalConversations ?? 0)")
  }

  // MARK: - Persistence

  private func saveAnalyticsData() {
    guard let context = modelContext else { return }

    do {
      try context.save()
    } catch {
      AppLogger.data.error("Failed to save analytics data: \(error)")
    }
  }

  // MARK: - Public Getters

  var totalTimeSpent: String {
    analyticsData?.formattedTimeSpent ?? "0m"
  }

  var totalAIResponses: Int {
    analyticsData?.totalAIResponsesGenerated ?? 0
  }

  var totalUserResponses: Int {
    analyticsData?.totalUserResponses ?? 0
  }

  var averageConversationDepth: Double {
    analyticsData?.averageConversationDepth ?? 0.0
  }

  var hasAnyData: Bool {
    guard let data = analyticsData else { return false }
    return data.totalSecondsSpent > 0 || data.totalAIResponsesGenerated > 0
      || data.totalUserResponses > 0
  }
}

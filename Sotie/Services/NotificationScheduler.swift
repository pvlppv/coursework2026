
import Combine
import Foundation
import os
import SwiftData
import UserNotifications

/// Smart notification scheduling for re-engagement
/// Handles follow-up notifications after entries and re-engagement for inactive users
@MainActor
final class NotificationScheduler: ObservableObject {

  // MARK: - Singleton

  static let shared = NotificationScheduler()

  private init() {}

  // MARK: - Private Properties

  private let center = UNUserNotificationCenter.current()
  private var modelContext: ModelContext?

  // UserDefaults keys
  private let lastAppOpenKey = "NotificationScheduler.lastAppOpenDate"

  // MARK: - Configuration

  func configure(context: ModelContext) {
    self.modelContext = context
    AppLogger.notifications.info("NotificationScheduler configured")
  }

  // MARK: - Daily Reminders (Morning + Evening)

  /// Schedule both morning and evening reminders based on the supplied preferences.
  /// Each slot is independently enabled/disabled and timed.
  /// Bodies are randomized at fire time? No — iOS caches the trigger content,
  /// so we set the body now and let the next reschedule (next preferences save
  /// or app launch) refresh it. Daily reminders re-randomize whenever
  /// `scheduleDailyReminders(with:)` runs.
  func scheduleDailyReminders(with preferences: NotificationPreferences) async {
    await scheduleMorningReminder(
      enabled: preferences.morningReminderEnabled,
      at: preferences.morningReminderTime
    )
    await scheduleEveningReminder(
      enabled: preferences.eveningReminderEnabled,
      at: preferences.eveningReminderTime
    )
  }

  func scheduleMorningReminder(enabled: Bool, at time: DateComponents) async {
    let identifier = NotificationType.morningReminder.identifier
    NotificationManager.shared.removePendingNotifications(withIdentifiers: [identifier])

    guard enabled else {
      AppLogger.notifications.info("Morning reminder disabled, removed pending request")
      return
    }

    let template = NotificationContentTemplate.template(for: .morningReminder)
    await scheduleRepeatingDaily(
      identifier: identifier,
      type: .morningReminder,
      template: template,
      time: time
    )
  }

  func scheduleEveningReminder(enabled: Bool, at time: DateComponents) async {
    let identifier = NotificationType.eveningReminder.identifier
    NotificationManager.shared.removePendingNotifications(withIdentifiers: [identifier])

    guard enabled else {
      AppLogger.notifications.info("Evening reminder disabled, removed pending request")
      return
    }

    let template = NotificationContentTemplate.template(for: .eveningReminder)
    await scheduleRepeatingDaily(
      identifier: identifier,
      type: .eveningReminder,
      template: template,
      time: time
    )
  }

  private func scheduleRepeatingDaily(
    identifier: String,
    type: NotificationType,
    template: NotificationContentTemplate,
    time: DateComponents
  ) async {
    let content = UNMutableNotificationContent()
    content.title = template.title
    content.body = template.body
    content.sound = template.sound
    content.categoryIdentifier = type.categoryIdentifier
    content.userInfo = ["type": type.rawValue]

    let trigger = UNCalendarNotificationTrigger(
      dateMatching: time,
      repeats: true
    )

    let request = UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: trigger
    )

    do {
      try await center.add(request)
      AppLogger.notifications.info(
        "Scheduled \(type.rawValue) at \(time.hour ?? 0):\(String(format: "%02d", time.minute ?? 0))"
      )
    } catch {
      AppLogger.notifications.error("Failed to schedule \(type.rawValue): \(error)")
    }
  }

  // MARK: - App Open Tracking

  /// Update last app open date - call this on every app launch/foreground
  func updateLastAppOpen() {
    let now = Date()
    UserDefaults.standard.set(now, forKey: lastAppOpenKey)

    AppLogger.notifications.info("Updated last app open: \(now)")

    Task {
      await cancelAllPendingFollowUps()
      await refreshReEngagementNotifications()
    }
  }

  /// Cancel all pending follow-up notifications.
  /// Called when the user returns to the app — if they're actively using it,
  /// they don't need a "what changed?" nudge.
  private func cancelAllPendingFollowUps() async {
    let pendingRequests = await center.pendingNotificationRequests()
    let followUpIds = pendingRequests
      .filter { $0.identifier.hasPrefix(NotificationType.conversationFollowUp.identifier) }
      .map(\.identifier)

    guard !followUpIds.isEmpty else { return }

    center.removePendingNotificationRequests(withIdentifiers: followUpIds)
    AppLogger.notifications.info("Cancelled \(followUpIds.count) pending follow-up notifications on app open")
  }

  // MARK: - Follow-Up Notification (Per-Entry, Zero LLM Cost)

  /// Schedule a follow-up notification 1-4 hours after user creates an entry.
  /// Body is the last paragraph of the AI's most recent response — picks up the
  /// thread without needing a fresh LLM call. Falls back to a static template
  /// if no AI response is available (edge case).
  ///
  /// Each entry gets its own notification (per-entry follow-ups). Triggers when
  /// the AI has spoken at least once, regardless of whether the user replied —
  /// the goal is to nudge the user back into the thread.
  /// - Parameter entry: The entry that was just saved
  func scheduleConversationFollowUp(for entry: Entry) async {
    guard NotificationManager.shared.isRegistered else {
      AppLogger.notifications.warning("Notifications not enabled, skipping follow-up")
      return
    }

    // Only schedule if there was at least one AI response in the conversation.
    // We use that AI response (last paragraph) as the notification body.
    let aiResponse = entry.lastAIResponse
    guard let aiResponse, !aiResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      AppLogger.notifications.warning("No AI response in entry, skipping follow-up notification")
      return
    }

    // Per-entry identifier — allows multiple follow-ups for different entries
    let identifier = followUpIdentifier(for: entry.id)

    // Cancel existing follow-up for this entry (user may have continued the conversation)
    let pendingRequests = await center.pendingNotificationRequests()
    if pendingRequests.contains(where: { $0.identifier == identifier }) {
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      AppLogger.notifications.info("Replacing existing follow-up for entry: \(entry.id)")
    }

    // Count existing pending follow-ups for smart spacing
    let existingFollowUpCount = pendingRequests.filter {
      $0.identifier.hasPrefix(NotificationType.conversationFollowUp.identifier)
    }.count

    // Base delay: 1-4 hours, plus 30-min offset per existing follow-up
    let minDelay: TimeInterval = 1 * 60 * 60  // 1 hour
    let maxDelay: TimeInterval = 4 * 60 * 60  // 4 hours
    let spacingOffset = TimeInterval(existingFollowUpCount) * 30 * 60  // 30 min per existing
    let randomDelay = TimeInterval.random(in: minDelay...maxDelay) + spacingOffset

    #if DEBUG
      let hours = Int(randomDelay / 3600)
      let minutes = Int((randomDelay.truncatingRemainder(dividingBy: 3600)) / 60)
      AppLogger.notifications.info("Scheduling follow-up in \(hours)h \(minutes)m for entry: \(entry.id)")
    #endif

    // Body = last paragraph of the AI's most recent response.
    // iOS will truncate on the lock screen automatically — long-press shows full text.
    let body = Self.lastParagraph(of: aiResponse)
    let template = NotificationContentTemplate.template(for: .conversationFollowUp, question: body)

    let content = UNMutableNotificationContent()
    content.title = template.title
    content.body = template.body
    content.sound = template.sound
    content.categoryIdentifier = NotificationType.conversationFollowUp.categoryIdentifier

    content.userInfo = [
      "type": NotificationType.conversationFollowUp.rawValue,
      "entryId": entry.id.uuidString,
      "entryDate": entry.date.timeIntervalSince1970,
    ]

    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: randomDelay,
      repeats: false
    )

    let request = UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: trigger
    )

    do {
      try await center.add(request)

      // Mark entry as having a pending notification
      entry.notificationSentAt = Date().addingTimeInterval(randomDelay)
      try? entry.modelContext?.save()

      AppLogger.notifications.info("Scheduled follow-up notification for entry: \(entry.id)")
    } catch {
      AppLogger.notifications.error("Failed to schedule follow-up notification: \(error)")
    }
  }

  /// Extract the last non-empty paragraph from an AI response.
  /// Splits on blank lines (`\n\n`); if there are no paragraph breaks, returns the
  /// trimmed full text. Used as the notification body so the user sees a meaningful
  /// fragment of the conversation rather than a generic prompt.
  static func lastParagraph(of text: String) -> String {
    let paragraphs = text
      .components(separatedBy: "\n\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return paragraphs.last ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Per-entry notification identifier
  private func followUpIdentifier(for entryId: UUID) -> String {
    "\(NotificationType.conversationFollowUp.identifier)_\(entryId.uuidString)"
  }

  /// Cancel follow-up notification for a specific entry
  func cancelFollowUpForEntry(_ entryId: UUID) {
    let identifier = followUpIdentifier(for: entryId)
    center.removePendingNotificationRequests(withIdentifiers: [identifier])

    AppLogger.notifications.info("Cancelled follow-up for entry: \(entryId)")
  }

  // MARK: - Re-Engagement Notifications (Fallback Only, No AI)

  /// Schedule a re-engagement notification using fallback templates — zero LLM cost.
  private func scheduleReEngagement(for entry: Entry, schedule: ReEngagementSchedule) async {
    AppLogger.notifications.info("Scheduling re-engagement notification for \(schedule.days) days")

    // Use fallback template — no AI generation
    let template = NotificationContentTemplate.fallbackTemplate(for: .reEngagement)

    let content = UNMutableNotificationContent()
    content.title = template.title
    content.body = template.body
    content.sound = template.sound
    content.categoryIdentifier = NotificationType.reEngagement.categoryIdentifier

    content.userInfo = [
      "type": NotificationType.reEngagement.rawValue,
      "daysSinceLastOpen": schedule.days,
      "entryId": entry.id.uuidString,
      "entryDate": entry.date.timeIntervalSince1970,
    ]

    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: schedule.fireDate.timeIntervalSinceNow,
      repeats: false
    )

    let request = UNNotificationRequest(
      identifier: schedule.identifier,
      content: content,
      trigger: trigger
    )

    do {
      try await center.add(request)
      AppLogger.notifications.info("Scheduled re-engagement notification: \(schedule.identifier)")
    } catch {
      AppLogger.notifications.error("Failed to schedule re-engagement notification: \(error)")
    }
  }

  /// Re-evaluates re-engagement notifications after entry mutations so pending prompts stay in sync.
  /// Reference date is always derived from the last entry — milestones fire N days after the user's last journal entry.
  /// Only schedules milestones that are still in the future (with a minimum 1-hour buffer)
  /// to avoid firing re-engagement notifications immediately after the user opens the app.
  func refreshReEngagementNotifications() async {
    cancelPendingReEngagementNotifications()

    guard NotificationManager.shared.isRegistered else { return }
    guard let context = modelContext else { return }

    guard let lastEntry = await getLastEntry(from: context) else {
      AppLogger.notifications.warning("No entries found, skipping re-engagement schedule refresh")
      return
    }

    let referenceDate = lastEntry.date
    let now = Date()
    // Minimum buffer: only schedule notifications that fire at least 1 hour from now.
    // This prevents re-engagement notifications from firing right after the user opens the app.
    let minimumFireDate = now.addingTimeInterval(1 * 60 * 60)

    for schedule in ReEngagementSchedulePlanner.schedule(from: referenceDate) {
      guard schedule.fireDate > minimumFireDate else {
        AppLogger.notifications.info(
          "Skipping re-engagement milestone \(schedule.days)d — fire date is in the past or too soon"
        )
        continue
      }
      await scheduleReEngagement(for: lastEntry, schedule: schedule)
    }
  }

  private func cancelPendingReEngagementNotifications() {
    center.removePendingNotificationRequests(withIdentifiers: ReEngagementSchedulePlanner.identifiers)
  }

  // MARK: - Data Fetching

  private func getLastEntry(from context: ModelContext) async -> Entry? {
    var descriptor = FetchDescriptor<Entry>(
      sortBy: [SortDescriptor(\Entry.date, order: .reverse)]
    )
    descriptor.fetchLimit = 1

    do {
      let entries = try context.fetch(descriptor)
      return entries.first
    } catch {
      AppLogger.notifications.error("Failed to fetch last entry: \(error)")
      return nil
    }
  }

  // MARK: - Legacy: Onboarding Resume Nudge (Removed)
  //
  // The onboarding resume nudge campaign was disabled when onboarding became
  // hard-paywall (no skip path). The cancel API is preserved as a no-op-style
  // defensive cleanup so any pending notifications from older app versions
  // are cleared the next time `PremiumManager` calls it (purchase / restore /
  // transaction-update).

  /// Cancel any leftover onboarding resume nudge notifications from older app
  /// versions. New installs never schedule these; this only matters for users
  /// upgrading from a build that did.
  func cancelOnboardingResumeNudges() {
    let legacyType = "onboarding_resume_nudge"
    let baseIdentifier = "\(DeveloperConfig.appBundleID).notification.\(legacyType)"
    let identifiers = [
      "\(baseIdentifier)_step1",
      "\(baseIdentifier)_step2",
    ]
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  // MARK: - Cleanup

  /// Remove all pending notifications (kept for compatibility)
  func removeAllPendingNotifications() {
    center.removeAllPendingNotificationRequests()

    AppLogger.notifications.info("Cleared all pending notifications")
  }
}

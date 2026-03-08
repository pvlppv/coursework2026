//
//  NotificationModels.swift
//  Sotie
//
//  Created by AI Assistant on 23.10.2025.
//

import Foundation
import UserNotifications

// MARK: - Notification Types

/// Types of notifications the app can send
enum NotificationType: String, Codable, CaseIterable {
  case morningReminder = "morning_reminder"
  case eveningReminder = "evening_reminder"
  case conversationFollowUp = "conversation_follow_up"
  case reEngagement = "re_engagement"

  nonisolated var identifier: String {
    "\(DeveloperConfig.appBundleID).notification.\(rawValue)"
  }

  nonisolated var categoryIdentifier: String {
    "SOTIE_\(rawValue.uppercased())"
  }

  /// Localization key for notification settings title
  nonisolated var titleKey: String {
    "notifications.type.\(rawValue).title"
  }

  /// Localization key for notification settings description
  nonisolated var descriptionKey: String {
    "notifications.type.\(rawValue).description"
  }
}

// MARK: - Notification Content Template

/// Template for notification content with AI-generated responses
struct NotificationContentTemplate {
  let title: String
  let body: String
  let sound: UNNotificationSound
  let badge: NSNumber?

  /// App display name used as the notification title so iOS renders the body in full multi-line mode.
  private static var appDisplayName: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Sotie Journal"
  }

  static func template(
    for type: NotificationType,
    question: String? = nil,
    context: NotificationContext = .default
  ) -> NotificationContentTemplate {
    switch type {
    case .morningReminder:
      // Morning reminder uses prompt card opener strings (morning sub-state).
      // Falls back to the first morning opener key directly if the random pick
      // somehow returns empty (should never happen in practice).
      let body = randomOpener(for: .morning)
        ?? localizedString("prompts.openers.morning.1", languageCode: currentLanguageCode)
      return NotificationContentTemplate(
        title: appDisplayName,
        body: body,
        sound: .default,
        badge: nil
      )

    case .eveningReminder:
      // Evening reminder uses prompt card opener strings (evening sub-state).
      let body = randomOpener(for: .evening)
        ?? localizedString("prompts.openers.evening.1", languageCode: currentLanguageCode)
      return NotificationContentTemplate(
        title: appDisplayName,
        body: body,
        sound: .default,
        badge: nil
      )

    case .conversationFollowUp, .reEngagement:
      // For follow-up and re-engagement, use question if provided
      if let question = question, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return NotificationContentTemplate(
          title: appDisplayName,
          body: question,
          sound: .default,
          badge: nil
        )
      }
      // Fallback
      return fallbackTemplate(for: type)
    }
  }

  static func fallbackTemplate(for type: NotificationType) -> NotificationContentTemplate {
    switch type {
    case .morningReminder:
      return NotificationContentTemplate(
        title: appDisplayName,
        body: randomOpener(for: .morning)
          ?? localizedString("prompts.openers.morning.1", languageCode: currentLanguageCode),
        sound: .default,
        badge: nil
      )

    case .eveningReminder:
      return NotificationContentTemplate(
        title: appDisplayName,
        body: randomOpener(for: .evening)
          ?? localizedString("prompts.openers.evening.1", languageCode: currentLanguageCode),
        sound: .default,
        badge: nil
      )

    case .conversationFollowUp:
      return NotificationContentTemplate(
        title: appDisplayName,
        body: appLocalizedString(Localizable.notificationFollowUpFallback),
        sound: .default,
        badge: nil
      )

    case .reEngagement:
      return NotificationContentTemplate(
        title: appDisplayName,
        body: appLocalizedString(Localizable.notificationReEngagementFallback),
        sound: .default,
        badge: nil
      )
    }
  }

  /// Pick a random localized opener string for a prompt sub-state.
  /// Used for morning/evening daily reminders — reuses the prompt card pool
  /// so notification copy and in-app prompt cards stay aligned.
  private static func randomOpener(for category: PromptCategory) -> String? {
    let openers = PromptCatalog.openers(for: category, languageCode: currentLanguageCode)
      .filter { !$0.isEmpty }
    return openers.randomElement()
  }

  /// Localized fallback questions for follow-up / re-engagement notifications.
  /// Used for testing the localization layer; runtime templates use this list
  /// indirectly through `fallbackTemplate(for:)`.
  static func fallbackQuestions(for type: NotificationType, languageCode: String) -> [String] {
    switch type {
    case .conversationFollowUp:
      return [localizedString(Localizable.notificationFollowUpFallback, languageCode: languageCode)]

    case .reEngagement:
      return [localizedString(Localizable.notificationReEngagementFallback, languageCode: languageCode)]

    case .morningReminder, .eveningReminder:
      return []
    }
  }

  private static var currentLanguageCode: String {
    LanguageManager.storedOrDefaultLanguageCode()
  }
}

// MARK: - Notification Preferences

/// User preferences for notifications.
///
/// Two daily slots — morning and evening — each with its own enabled flag
/// and time. Bodies pull from the prompt-card opener pool (morning slot →
/// morning openers, evening slot → evening openers) so notification copy
/// stays aligned with what the user sees on the AddEntry rail.
struct NotificationPreferences: Codable {
  var morningReminderEnabled: Bool
  var morningReminderTime: DateComponents
  var eveningReminderEnabled: Bool
  var eveningReminderTime: DateComponents

  static let `default` = NotificationPreferences(
    morningReminderEnabled: true,
    morningReminderTime: DateComponents(hour: 9, minute: 0),
    eveningReminderEnabled: true,
    eveningReminderTime: DateComponents(hour: 21, minute: 0)
  )

  // UserDefaults keys
  private static let preferencesKey = "NotificationPreferences"

  // Custom initializer (required because we have custom Codable)
  init(
    morningReminderEnabled: Bool,
    morningReminderTime: DateComponents,
    eveningReminderEnabled: Bool,
    eveningReminderTime: DateComponents
  ) {
    self.morningReminderEnabled = morningReminderEnabled
    self.morningReminderTime = morningReminderTime
    self.eveningReminderEnabled = eveningReminderEnabled
    self.eveningReminderTime = eveningReminderTime
  }

  // Custom Codable implementation for DateComponents
  enum CodingKeys: String, CodingKey {
    case morningReminderEnabled
    case morningReminderHour
    case morningReminderMinute
    case eveningReminderEnabled
    case eveningReminderHour
    case eveningReminderMinute
    // Legacy keys (single daily reminder) — decoded for backward compatibility.
    case dailyReminderEnabled
    case dailyReminderHour
    case dailyReminderMinute
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    // Try the new schema first.
    if container.contains(.morningReminderEnabled) || container.contains(.eveningReminderEnabled) {
      morningReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .morningReminderEnabled) ?? false
      let mHour = try container.decodeIfPresent(Int.self, forKey: .morningReminderHour) ?? 9
      let mMinute = try container.decodeIfPresent(Int.self, forKey: .morningReminderMinute) ?? 0
      morningReminderTime = DateComponents(hour: mHour, minute: mMinute)

      eveningReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .eveningReminderEnabled) ?? false
      let eHour = try container.decodeIfPresent(Int.self, forKey: .eveningReminderHour) ?? 21
      let eMinute = try container.decodeIfPresent(Int.self, forKey: .eveningReminderMinute) ?? 0
      eveningReminderTime = DateComponents(hour: eHour, minute: eMinute)
      return
    }

    // Fallback: migrate from legacy single daily reminder.
    // Old behavior was a single reminder defaulting to 20:00.
    // We migrate it onto the evening slot to preserve the user's choice.
    let legacyEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyReminderEnabled) ?? false
    let legacyHour = try container.decodeIfPresent(Int.self, forKey: .dailyReminderHour) ?? 21
    let legacyMinute = try container.decodeIfPresent(Int.self, forKey: .dailyReminderMinute) ?? 0

    morningReminderEnabled = false
    morningReminderTime = DateComponents(hour: 9, minute: 0)
    eveningReminderEnabled = legacyEnabled
    eveningReminderTime = DateComponents(hour: legacyHour, minute: legacyMinute)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(morningReminderEnabled, forKey: .morningReminderEnabled)
    try container.encode(morningReminderTime.hour ?? 9, forKey: .morningReminderHour)
    try container.encode(morningReminderTime.minute ?? 0, forKey: .morningReminderMinute)
    try container.encode(eveningReminderEnabled, forKey: .eveningReminderEnabled)
    try container.encode(eveningReminderTime.hour ?? 21, forKey: .eveningReminderHour)
    try container.encode(eveningReminderTime.minute ?? 0, forKey: .eveningReminderMinute)
  }

  static func load() -> NotificationPreferences {
    guard let data = UserDefaults.standard.data(forKey: preferencesKey),
      let prefs = try? JSONDecoder().decode(NotificationPreferences.self, from: data)
    else {
      return .default
    }
    return prefs
  }

  func save() {
    if let data = try? JSONEncoder().encode(self) {
      UserDefaults.standard.set(data, forKey: Self.preferencesKey)
    }
  }
}

// MARK: - Notification Context

/// Context data for scheduling follow-up and re-engagement notifications.
struct NotificationContext {
  let entryText: String
  let conversationHistory: [DialogueMessage]
  let entryDate: Date
  let inactivityDays: Int?

  // For daily reminders (simpler context)
  nonisolated static let `default` = NotificationContext(
    entryText: "",
    conversationHistory: [],
    entryDate: Date(),
    inactivityDays: nil
  )
}

struct ReEngagementSchedule: Equatable {
  let days: Int
  let fireDate: Date

  var identifier: String {
    "\(NotificationType.reEngagement.identifier)_\(days)d"
  }
}

enum ReEngagementSchedulePlanner {
  static let milestoneDays = [3, 7, 14, 30]

  static func schedule(from referenceDate: Date, calendar: Calendar = .current)
    -> [ReEngagementSchedule]
  {
    milestoneDays.compactMap { days in
      guard let fireDate = calendar.date(byAdding: .day, value: days, to: referenceDate) else {
        return nil
      }

      return ReEngagementSchedule(days: days, fireDate: fireDate)
    }
  }

  static var identifiers: [String] {
    milestoneDays.map { "\(NotificationType.reEngagement.identifier)_\($0)d" }
  }
}

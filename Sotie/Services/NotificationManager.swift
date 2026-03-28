import Combine
import Foundation
import os
import SwiftUI
import UserNotifications

/// Central notification management for smart re-engagement
/// Handles permissions, registration, and coordination with NotificationScheduler
@MainActor
final class NotificationManager: NSObject, ObservableObject {

  private struct PendingNotificationNavigation: Equatable, Sendable {
    let entryId: UUID?
    let notificationTypeString: String?
  }

  // MARK: - Singleton

  static let shared = NotificationManager()

  private override init() {
    super.init()
    prepareForLaunch()
  }

  // MARK: - Published Properties

  @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
  @Published var isRegistered: Bool = false
  @Published var preferences = NotificationPreferences.load()

  /// Attribution source for paywall views triggered by notification taps.
  /// Set when user taps a nudge notification; consumed by PaywallView.
  var paywallAttributionSource: String?

  // MARK: - Private Properties

  private let center = UNUserNotificationCenter.current()
  private var registrationAttempted: Bool {
    get { UserDefaults.standard.bool(forKey: "NotificationManager.registrationAttempted") }
    set { UserDefaults.standard.set(newValue, forKey: "NotificationManager.registrationAttempted") }
  }

  // Navigation router for deep linking from notifications
  weak var router: NavigationRouter?
  private var pendingNavigation: PendingNotificationNavigation?

  /// Timestamp of last notification-driven navigation.
  /// Used to debounce duplicate onOpenURL calls that iOS may fire alongside didReceive.
  private(set) var lastNotificationNavigationDate: Date?

  // MARK: - Configuration

  /// Prepare notification routing as early as possible during app launch.
  func prepareForLaunch() {
    center.delegate = self
    registerNotificationCategories()
  }

  /// Configure notification manager - call this during app launch
  func configure() async {
    prepareForLaunch()

    // Check current authorization status
    await updateAuthorizationStatus()

    AppLogger.notifications.info("NotificationManager configured with status: \(self.authorizationStatus.rawValue)")
  }

  // MARK: - Permission Management

  /// Request notification authorization from user
  func requestAuthorization() async -> Bool {
    registrationAttempted = true

    do {
      let granted = try await center.requestAuthorization(options: [
        .alert,
        .badge,
        .sound,
      ])

      await updateAuthorizationStatus()

      if granted {
        AppLogger.notifications.info("Notification authorization granted")
        isRegistered = true

        // Schedule morning + evening reminders if enabled in preferences
        let prefs = preferences
        await NotificationScheduler.shared.scheduleDailyReminders(with: prefs)
      } else {
        AppLogger.notifications.warning("Notification authorization denied")
      }

      return granted
    } catch {
      AppLogger.notifications.error("Failed to request notification authorization: \(error)")
      return false
    }
  }

  /// Check if we should prompt for notifications
  var shouldPromptForAuthorization: Bool {
    return authorizationStatus == .notDetermined && !registrationAttempted
  }

  /// Update current authorization status
  func updateAuthorizationStatus() async {
    let settings = await center.notificationSettings()
    authorizationStatus = settings.authorizationStatus

    // Update registration status
    isRegistered = authorizationStatus == .authorized || authorizationStatus == .provisional
  }

  /// Open system notification settings
  func openNotificationSettings() {
    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
      UIApplication.shared.open(url)
    }
  }

  // MARK: - Notification Categories

  /// Register notification categories (simple, no actions)
  private func registerNotificationCategories() {
    var categories = Set<UNNotificationCategory>()

    for type in NotificationType.allCases {
      let category = UNNotificationCategory(
        identifier: type.categoryIdentifier,
        actions: [],
        intentIdentifiers: [],
        options: []
      )
      categories.insert(category)
    }

    center.setNotificationCategories(categories)
    AppLogger.notifications.info("Registered \(categories.count) notification categories")
  }

  // MARK: - Preference Management

  /// Update notification preferences
  func updatePreferences(_ newPreferences: NotificationPreferences) async {
    preferences = newPreferences
    preferences.save()

    // Reschedule both daily reminder slots with new preferences.
    // Each slot independently honors its own enabled flag.
    if isRegistered {
      await NotificationScheduler.shared.scheduleDailyReminders(with: newPreferences)
    }
  }

  /// Check if any daily reminder slot is enabled
  func isDailyReminderEnabled() -> Bool {
    return preferences.morningReminderEnabled || preferences.eveningReminderEnabled
  }

  func attachRouter(_ router: NavigationRouter) {
    self.router = router
    processPendingNavigationIfNeeded()
  }

  func processPendingNavigationIfNeeded() {
    handlePendingNavigationIfPossible()
  }

  /// Toggle morning reminder
  func toggleMorningReminder() async {
    var newPrefs = preferences
    newPrefs.morningReminderEnabled.toggle()
    await updatePreferences(newPrefs)
  }

  /// Toggle evening reminder
  func toggleEveningReminder() async {
    var newPrefs = preferences
    newPrefs.eveningReminderEnabled.toggle()
    await updatePreferences(newPrefs)
  }

  // MARK: - Badge Management

  /// Update app badge count
  func updateBadgeCount(_ count: Int) {
    UNUserNotificationCenter.current().setBadgeCount(count)
  }

  /// Clear app badge
  func clearBadge() {
    updateBadgeCount(0)
  }

  // MARK: - Notification Management

  /// Get all pending notifications
  func getPendingNotifications() async -> [UNNotificationRequest] {
    return await center.pendingNotificationRequests()
  }

  /// Get all delivered notifications
  func getDeliveredNotifications() async -> [UNNotification] {
    return await center.deliveredNotifications()
  }

  /// Remove specific pending notifications
  func removePendingNotifications(withIdentifiers identifiers: [String]) {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  /// Remove all pending notifications
  func removeAllPendingNotifications() {
    center.removeAllPendingNotificationRequests()
  }

  /// Remove delivered notifications
  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  /// Clear all delivered notifications
  func clearAllDeliveredNotifications() {
    center.removeAllDeliveredNotifications()
    clearBadge()
  }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

  nonisolated static func foregroundPresentationOptions(
    for userInfo: [AnyHashable: Any],
    presentedSheet: SheetDestination?
  ) -> UNNotificationPresentationOptions {
    guard
      let type = userInfo["type"] as? String,
      type == NotificationType.conversationFollowUp.rawValue,
      let entryIdString = userInfo["entryId"] as? String,
      let entryId = UUID(uuidString: entryIdString),
      currentlyEditedEntryId(from: presentedSheet) == entryId
    else {
      return [.banner, .sound, .badge]
    }

    return []
  }

  nonisolated private static func currentlyEditedEntryId(from presentedSheet: SheetDestination?) -> UUID? {
    switch presentedSheet {
    case .editEntry(let entry):
      return entry.id
    case .editEntryById(let entryId):
      return entryId
    default:
      return nil
    }
  }

  /// Handle notification when app is in foreground
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let options = Self.foregroundPresentationOptions(
      for: notification.request.content.userInfo,
      presentedSheet: MainActor.assumeIsolated { router?.presentedSheet }
    )
    completionHandler(options)
  }

  /// Handle notification tap — uses completion handler variant for guaranteed main thread safety.
  /// The `nonisolated async` variant causes "Call must be made on main thread" crashes
  /// because `await MainActor.run` does not reliably land on the main thread
  /// during app background→foreground transitions.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let actionIdentifier = response.actionIdentifier
    let userInfo = response.notification.request.content.userInfo

    // Extract all values on the current thread (avoid Sendable issues)
    let entryIdString = userInfo["entryId"] as? String
    let entryId = entryIdString.flatMap { UUID(uuidString: $0) }
    let notificationTypeString = userInfo["type"] as? String

    AppLogger.notifications.info("Notification tapped: type=\(notificationTypeString ?? "unknown"), entryId=\(entryIdString ?? "none")")

    // Dispatch ALL state mutations to main thread explicitly.
    // The nonisolated async variant + MainActor.run crashes during background→foreground
    // transitions ("Call must be made on main thread"), so we use DispatchQueue.main.async.
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        completionHandler()
        return
      }

      // Track notification tap
      if actionIdentifier == UNNotificationDefaultActionIdentifier {
        Analytics.notificationTapped(type: notificationTypeString ?? "unknown")

        // Enqueue navigation
        self.lastNotificationNavigationDate = Date()
        self.enqueueNotificationNavigation(
          PendingNotificationNavigation(
            entryId: entryId,
            notificationTypeString: notificationTypeString
          )
        )
      }

      // Clear badge
      self.clearBadge()

      completionHandler()
    }
  }

  private func enqueueNotificationNavigation(_ navigation: PendingNotificationNavigation) {
    pendingNavigation = navigation
    handlePendingNavigationIfPossible()
  }

  private func handlePendingNavigationIfPossible() {
    guard let pendingNavigation else { return }
    guard let router else {
      AppLogger.notifications.info("Notification navigation deferred — router not yet attached")
      return
    }

    // Dismiss any currently open sheet (e.g. Settings) before navigating
    router.dismissSheet()

    if pendingNavigation.notificationTypeString == NotificationType.conversationFollowUp.rawValue,
      let entryId = pendingNavigation.entryId
    {
      NotificationScheduler.shared.cancelFollowUpForEntry(entryId)
    }

    defer {
      self.pendingNavigation = nil
    }

    if let entryId = pendingNavigation.entryId {
      AppLogger.notifications.info("Notification navigating to entry: \(entryId)")
      router.navigateToEntry(withId: entryId)
      return
    }

    AppLogger.notifications.info("Notification navigating to home")
    router.selectTab(.home)
    HapticManager.shared.gentle()
  }
}

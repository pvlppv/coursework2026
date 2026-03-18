import Combine
import os
import SwiftUI

// Tab enum for tab selection
enum Tab: String, CaseIterable {
  case home = "home"
}

// Sheet presentation states
enum SheetDestination: Identifiable, Equatable {
  case addEntry
  case editEntry(entry: Entry)
  case editEntryById(entryId: UUID)  // For deep linking when we need to fetch entry
  case settings
  case reflectionsCalendar
  case customView(AnyView)

  var id: String {
    switch self {
    case .addEntry:
      return "addEntry"
    case .editEntry(let entry):
      return "editEntry_\(entry.id)"
    case .editEntryById(let entryId):
      return "editEntryById_\(entryId)"
    case .settings:
      return "settings"
    case .reflectionsCalendar:
      return "reflectionsCalendar"
    case .customView(_):
      return "customView"
    }
  }

  // Equatable conformance
  static func == (lhs: SheetDestination, rhs: SheetDestination) -> Bool {
    lhs.id == rhs.id
  }
}

// NavigationRouter manages app-wide navigation state
@MainActor
class NavigationRouter: ObservableObject {
  @Published var selectedTab: Tab = .home
  @Published var homeNavigationPath = NavigationPath()
  @Published var presentedSheet: SheetDestination?
  @Published var entryScrollTarget: UUID?

  // MARK: - Tab Navigation
  func selectTab(_ tab: Tab) {
    selectedTab = tab
    // Note: Haptic feedback is handled in MainTabView.onChange
  }

  // MARK: - Sheet Presentation

  /// Backup destination in case SwiftUI ignores the assignment during a dismiss animation.
  private var pendingSheetDestination: SheetDestination?

  func presentSheet(_ destination: SheetDestination) {
    guard presentedSheet != destination else { return }

    // Always try to set directly — SwiftUI natively replaces sheets
    // when the item identity changes.
    presentedSheet = destination

    // Save as backup: if SwiftUI is mid-dismiss animation and ignores
    // the assignment, sheetDidDismiss() will retry.
    pendingSheetDestination = destination
  }

  /// Called from MainTabView `.onChange` when a sheet successfully opens (nil → non-nil).
  /// Clears the backup since presentation succeeded.
  func sheetDidPresent() {
    pendingSheetDestination = nil
  }

  /// Called from MainTabView `.sheet(onDismiss:)` when the dismiss animation is fully complete.
  /// If something was queued during the animation, present it now.
  func sheetDidDismiss() {
    guard let destination = pendingSheetDestination else { return }
    pendingSheetDestination = nil
    presentedSheet = destination
  }

  func dismissSheet() {
    pendingSheetDestination = nil
    presentedSheet = nil
  }

  func clearEntryScrollTarget(_ entryId: UUID? = nil) {
    guard entryId == nil || entryScrollTarget == entryId else { return }
    entryScrollTarget = nil
  }

  // MARK: - Programmatic Navigation

  func presentCustomView(_ view: AnyView) {
    presentSheet(.customView(view))  // customView shares a single slot
  }

  // MARK: - Navigation Path Management
  func clearNavigationPath(for tab: Tab) {
    switch tab {
    case .home:
      homeNavigationPath = NavigationPath()
    }
  }

  func popToRoot(for tab: Tab) {
    clearNavigationPath(for: tab)
  }

  // MARK: - Deep Link Handling

  /// Handle deep links from notifications and external sources
  /// Supports: sotiejournal://entry/UUID - Navigate to specific entry
  ///           sotiejournal://create - Present entry creation
  func handleDeepLink(url: URL) {
    guard url.scheme == "sotiejournal" else {
      AppLogger.app.warning("Invalid deep link scheme: \(url.scheme ?? "nil")")
      return
    }

    AppLogger.app.info("Handling deep link: \(url.absoluteString)")

    switch url.host {
    case "entry":
      // Extract entry UUID from path: sotiejournal://entry/UUID
      let pathComponents = url.pathComponents.filter { $0 != "/" }
      if let entryIdString = pathComponents.first,
        let entryId = UUID(uuidString: entryIdString)
      {
        AppLogger.app.info("Deep link routing to entry: \(entryId)")
        navigateToEntry(withId: entryId)
      } else {
        AppLogger.app.warning("Invalid entry UUID in deep link: \(url.path)")
        // Fallback to home
        selectTab(.home)
        HapticManager.shared.gentle()
      }

    case "create":
      // Present entry creation sheet: sotiejournal://create
      presentSheet(.addEntry)
      HapticManager.shared.gentle()

    case "home", nil:
      // Navigate to home tab: sotiejournal://home or sotiejournal://
      selectTab(.home)
      HapticManager.shared.gentle()

    case "onboarding":
      // Discount squeeze deep link: sotiejournal://onboarding/discount
      // Routed by OnboardingContainerView via the activity manager flag.
      // The container only renders during onboarding, so no-op when the
      // user has already finished it (Live Activity should have ended).
      let pathComponents = url.pathComponents.filter { $0 != "/" }
      if pathComponents.first == "discount" {
        AppLogger.app.info("Deep link: onboarding discount paywall")
        OnboardingDiscountActivityManager.shared.requestPresentation()
        HapticManager.shared.gentle()
      } else {
        AppLogger.app.warning("Unknown onboarding deep-link path: \(url.path)")
      }

    default:
      AppLogger.app.warning("Unknown deep link host: \(url.host ?? "nil")")
      // Fallback to home
      selectTab(.home)
      HapticManager.shared.gentle()
    }
  }

  // MARK: - Entry Navigation

  /// Closure to validate entry existence before presenting sheet.
  /// Set by the view layer (ContentView) which has access to modelContext.
  /// If nil (not yet set during cold start), navigateToEntry proceeds optimistically.
  var entryExists: ((UUID) -> Bool)?

  /// Navigate to a specific entry by ID (used for notifications).
  /// If entry doesn't exist, navigates to home without presenting a sheet.
  @discardableResult
  func navigateToEntry(withId entryId: UUID) -> Bool {
    selectedTab = .home

    // Gate: validate entry exists before presenting sheet
    if let entryExists, !entryExists(entryId) {
      AppLogger.notifications.info("Entry not found: \(entryId) — navigating home")
      return false
    }

    entryScrollTarget = entryId
    presentSheet(.editEntryById(entryId: entryId))
    HapticManager.shared.gentle()
    return true
  }
}

import SwiftData
import os
import SwiftUI

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var appViewModel = AppViewModel()
  @StateObject private var dashboardViewModel = DashboardViewModel()
  @StateObject private var languageManager = LanguageManager.shared
  @StateObject private var notificationManager = NotificationManager.shared
  @StateObject private var router = NavigationRouter()

  /// Owned at the root so the discount paywall sheet survives the
  /// onboarding → main app transition. The Live Activity can be
  /// tapped at any moment (during onboarding *or* after the user
  /// finished it but the squeeze still has time on the clock), and
  /// the sheet needs to be reachable from both states. Hosting it on
  /// `OnboardingContainerView` alone meant a tap after onboarding
  /// would flip the flag against a view that wasn't on screen — the
  /// "screen opens and closes immediately" symptom.
  @StateObject private var discountActivity = OnboardingDiscountActivityManager.shared

  @State private var isInitialized = false
  @State private var showUITestPaywall = false
  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
  private let uiTestOverrides = UITestOverrides.current

  var body: some View {
    Group {
      if !hasCompletedOnboarding {
        OnboardingContainerView(isCompleted: $hasCompletedOnboarding)
          .transition(.opacity)
      } else {
        MainTabView()
          .transition(.opacity)
          .environmentObject(appViewModel)
          .environmentObject(dashboardViewModel)
          .environmentObject(languageManager)
          .environmentObject(notificationManager)
          .environmentObject(router)
          .environment(\.locale, languageManager.locale)
          .task(priority: .userInitiated) {
            // Only initialize once on first launch
            guard !isInitialized else { return }

            // Set up entry existence check so notification navigation
            // can validate entries before presenting sheets.
            let ctx = modelContext
            router.entryExists = { entryId in
              let descriptor = FetchDescriptor<Entry>(
                predicate: #Predicate { entry in entry.id == entryId }
              )
              return (try? ctx.fetch(descriptor).first) != nil
            }

            // Attach router before async setup so pending notification taps can flush immediately.
            notificationManager.attachRouter(router)

            // Initialize app (fast, synchronous)
            appViewModel.initialize(with: modelContext)
            dashboardViewModel.initialize(with: modelContext)
            AnalyticsTracker.shared.initialize(with: modelContext)

            // Configure notification system (async) - run at lower priority
            await Task(priority: .utility) {
              guard !uiTestOverrides.isRunningUITests else { return }

              await notificationManager.configure()
              await MainActor.run {
                NotificationScheduler.shared.configure(context: modelContext)
              }

              // Auto-request notification permission on first launch
              if notificationManager.shouldPromptForAuthorization {
                _ = await notificationManager.requestAuthorization()
                // Notification permission dialog is friction for review prompt
                await MainActor.run {
                  ReviewManager.shared.recordSessionFriction()
                }
              }
            }.value

            isInitialized = true

            // Track app open for notification scheduling
            await MainActor.run {
              NotificationScheduler.shared.updateLastAppOpen()
              notificationManager.processPendingNavigationIfNeeded()
            }
          }
          .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
          }
          .onOpenURL { url in
            // Debounce: skip if a notification just handled this (iOS sometimes fires both)
            if let lastNav = NotificationManager.shared.lastNotificationNavigationDate,
               Date().timeIntervalSince(lastNav) < 2.0 {
              AppLogger.app.info("Skipping onOpenURL (notification just handled): \(url.absoluteString)")
              return
            }
            AppLogger.app.info("onOpenURL: \(url.absoluteString)")
            router.handleDeepLink(url: url)
          }
        // Language changes are reactive through @Published properties and .environment(\.locale)
        // No need for .id() which resets navigation
      }
    }
    .environmentObject(languageManager)
    .environment(\.locale, languageManager.locale)
    .animation(.easeInOut(duration: 0.5), value: hasCompletedOnboarding)
    .sheet(isPresented: $showUITestPaywall) {
      if let source = uiTestOverrides.paywallSource {
        PaywallView(
          source: source,
          isFirstPresentation: uiTestOverrides.showsFirstPresentationPaywall
        )
      }
    }
    // Single, root-level sheet for the onboarding discount squeeze.
    // Owned here (not on OnboardingContainerView) so a Live Activity
    // tap can present it whether the user is still in onboarding or
    // has already finished it.
    .sheet(isPresented: $discountActivity.shouldPresentDiscountPaywall) {
      DiscountPaywallView(onClose: {
        discountActivity.shouldPresentDiscountPaywall = false
      })
      .environment(\.theme, Theme())
      .environmentObject(languageManager)
      .environment(\.locale, languageManager.locale)
    }
    // Any path that flips the user to premium (paywall, restore,
    // parental approval) should silence the squeeze banner so the
    // lock screen doesn't keep advertising a discount they already
    // resolved.
    .onReceive(PremiumManager.shared.$subscriptionStatus) { status in
      if status.isPremium {
        discountActivity.subscriptionDidBecomePremium()
      }
    }
    .onAppear {
      if uiTestOverrides.forceCompletedOnboarding && !hasCompletedOnboarding {
        hasCompletedOnboarding = true
      }

      if uiTestOverrides.paywallSource != nil && !showUITestPaywall {
        showUITestPaywall = true
      }


    }
    .onChange(of: hasCompletedOnboarding) { _, completed in
      // No entrance animation reset needed
    }
  }

  // MARK: - Scene Phase Handling
  private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {

    switch newPhase {
    case .active:
      // App became active (returned from background) 1
      // No delay needed - let the app respond immediately
      if oldPhase == .background || oldPhase == .inactive {
        // Track app open for notification scheduling
        NotificationScheduler.shared.updateLastAppOpen()
        notificationManager.processPendingNavigationIfNeeded()

        // Reset review friction tracking for new session
        ReviewManager.shared.resetSessionFriction()

        // Track app resume for analytics
        Analytics.appResumed()

        // Refresh premium status in case subscription changed
        PremiumManager.shared.refreshSubscriptionStatus()

        // Reconcile notification authorization (user may have changed in Settings)
        Task {
          await notificationManager.updateAuthorizationStatus()
        }
      }
    case .background:
      break
    case .inactive:
      // App is transitioning - nothing to do
      break
    @unknown default:
      break
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: Entry.self, inMemory: true)
    .environment(\.theme, Theme())
}

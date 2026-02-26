import Foundation

nonisolated struct UITestOverrides: Equatable, Sendable {
  let isRunningUITests: Bool
  let forceCompletedOnboarding: Bool
  let paywallSource: PaywallSource?
  let forcedTrialEligibility: Bool?
  let showsFirstPresentationPaywall: Bool
  let usesStubPaywallPlans: Bool
  let forcePremiumEntitlement: Bool

  init(
    arguments: [String] = ProcessInfo.processInfo.arguments,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    let isRunningUITests = arguments.contains("SOTIE_UI_TESTS")
    self.isRunningUITests = isRunningUITests
    self.forceCompletedOnboarding = arguments.contains("SOTIE_UI_TEST_COMPLETED_ONBOARDING")
    self.forcePremiumEntitlement = arguments.contains("SOTIE_UI_TEST_FORCE_PREMIUM")
    if let rawTrialEligibility = environment["SOTIE_UI_TEST_TRIAL_ELIGIBLE"]?.lowercased() {
      switch rawTrialEligibility {
      case "true":
        self.forcedTrialEligibility = true
      case "false":
        self.forcedTrialEligibility = false
      default:
        self.forcedTrialEligibility = nil
      }
    } else {
      self.forcedTrialEligibility = nil
    }

    if let rawSource = environment["SOTIE_UI_TEST_PAYWALL_SOURCE"], !rawSource.isEmpty {
      let source = PaywallSource(rawValue: rawSource)
      self.paywallSource = source
      self.showsFirstPresentationPaywall = source == .onboardingCheckpoint
    } else {
      self.paywallSource = nil
      self.showsFirstPresentationPaywall = false
    }

    self.usesStubPaywallPlans = isRunningUITests && paywallSource != nil
  }

  static let current = UITestOverrides()
}

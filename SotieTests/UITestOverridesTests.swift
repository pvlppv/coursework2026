import Foundation
import Testing

@testable import Sotie

struct UITestOverridesTests {

  @Test func parsesCompletedOnboardingAndSettingsPaywallOverrides() throws {
    let overrides = UITestOverrides(
      arguments: [
        "SOTIE_UI_TESTS",
        "SOTIE_UI_TEST_COMPLETED_ONBOARDING",
      ],
      environment: [
        "SOTIE_UI_TEST_PAYWALL_SOURCE": "settings",
      ]
    )

    #expect(overrides.isRunningUITests)
    #expect(overrides.forceCompletedOnboarding)
    #expect(overrides.paywallSource == .settings)
    #expect(!overrides.showsFirstPresentationPaywall)
    #expect(overrides.usesStubPaywallPlans)
  }

  @Test func onboardingPaywallOverrideUsesFirstPresentationMode() throws {
    let overrides = UITestOverrides(
      arguments: ["SOTIE_UI_TESTS"],
      environment: [
        "SOTIE_UI_TEST_PAYWALL_SOURCE": "onboarding_checkpoint",
      ]
    )

    #expect(overrides.paywallSource == .onboardingCheckpoint)
    #expect(overrides.showsFirstPresentationPaywall)
  }

  @Test func parsesForcedTrialIneligibilityOverride() throws {
    let overrides = UITestOverrides(
      arguments: ["SOTIE_UI_TESTS"],
      environment: [
        "SOTIE_UI_TEST_PAYWALL_SOURCE": "settings",
        "SOTIE_UI_TEST_TRIAL_ELIGIBLE": "false",
      ]
    )

    #expect(overrides.paywallSource == .settings)
    #expect(overrides.forcedTrialEligibility == false)
  }
}

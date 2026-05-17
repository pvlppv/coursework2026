import XCTest

final class PaywallSmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
     func testSettingsPaywallShowsPlansAndFooterActions() throws {
         let app = XCUIApplication()
         app.launchArguments += ["SOTIE_UI_TESTS", "SOTIE_UI_TEST_COMPLETED_ONBOARDING"]
         app.launchEnvironment["SOTIE_UI_TEST_PAYWALL_SOURCE"] = "settings"
         app.launch()

         XCTAssertTrue(app.staticTexts["paywall-hero-title"].waitForExistence(timeout: 5))
         XCTAssertTrue(app.otherElements["paywall-purchase-dock"].waitForExistence(timeout: 5))
         XCTAssertTrue(app.buttons["paywall-plan-annual"].exists)
         XCTAssertTrue(app.buttons["paywall-plan-monthly"].exists)
         XCTAssertTrue(app.buttons["paywall-primary-cta"].waitForExistence(timeout: 5))
         XCTAssertTrue(app.staticTexts["paywall-subscription-disclaimer"].exists)
         XCTAssertTrue(app.buttons["paywall-restore"].exists)
         XCTAssertTrue(app.descendants(matching: .any)["paywall-terms"].exists)
         XCTAssertTrue(app.descendants(matching: .any)["paywall-privacy"].exists)
     }

    @MainActor
    func testOnboardingPaywallShowsDelayedMaybeLaterButton() throws {
        let app = XCUIApplication()
        app.launchArguments += ["SOTIE_UI_TESTS"]
        app.launchEnvironment["SOTIE_UI_TEST_PAYWALL_SOURCE"] = "onboarding_checkpoint"
        app.launch()

        XCTAssertTrue(app.staticTexts["paywall-hero-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["paywall-purchase-dock"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["paywall-primary-cta"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["paywall-plan-annual"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["paywall-maybe-later"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testIneligibleSettingsPaywallHidesTrialTimelineAndUsesAnnualCTA() throws {
        let app = XCUIApplication()
        app.launchArguments += ["SOTIE_UI_TESTS", "SOTIE_UI_TEST_COMPLETED_ONBOARDING"]
        app.launchEnvironment["SOTIE_UI_TEST_PAYWALL_SOURCE"] = "settings"
        app.launchEnvironment["SOTIE_UI_TEST_TRIAL_ELIGIBLE"] = "false"
        app.launch()

        XCTAssertTrue(app.staticTexts["paywall-hero-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["paywall-trial-timeline"].exists)
        XCTAssertTrue(app.otherElements["paywall-purchase-dock"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["paywall-primary-cta"].label, "Continue with Annual")
    }
}

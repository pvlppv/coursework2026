//
//  BackendGoDeeperE2ETests.swift
//  SotieUITests
//

import XCTest

final class BackendGoDeeperE2ETests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testGoDeeperStreamsThroughConfiguredBackend() throws {
    let app = XCUIApplication()
    app.launchArguments += [
      "SOTIE_UI_TESTS",
      "SOTIE_UI_TEST_COMPLETED_ONBOARDING",
      "SOTIE_UI_TEST_FORCE_PREMIUM",
    ]
    app.launchEnvironment["SOTIE_BACKEND_BASE_URL"] = "https://sotie.app"
    app.launch()

    let addReflection = app.buttons["Add Reflection"]
    XCTAssertTrue(addReflection.waitForExistence(timeout: 10))
    addReflection.tap()

    let journalField = app.textFields["journal-entry-field"]
    XCTAssertTrue(journalField.waitForExistence(timeout: 10))
    journalField.tap()
    journalField.typeText("I feel stuck but I want to test backend streaming.")

    let goDeeper = app.buttons["go-deeper-fab"]
    XCTAssertTrue(goDeeper.waitForExistence(timeout: 10))
    goDeeper.tap()

    XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "backend")).element.waitForExistence(timeout: 10))
  }
}

import Foundation
import SwiftUI
import Testing

@testable import Sotie

@MainActor
struct ComponentTests {

  // MARK: - Basic Component Smoke Test

  @Test func testSpacingConstantsAreAccessible() async throws {
    #expect(Spacing.small > 0)
    #expect(Spacing.medium >= Spacing.small)
  }
}

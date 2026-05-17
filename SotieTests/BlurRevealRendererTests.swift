import Foundation
import Testing

@testable import Sotie

struct BlurRevealRendererTests {

  @Test func completionThresholdKeepsShortMessagesAtExistingFloor() {
    let renderer = BlurRevealRenderer(elapsedTime: 0)

    #expect(renderer.completionThreshold(forCharacterCount: 1) == 10)
    #expect(renderer.completionThreshold(forCharacterCount: 24) == 10)
  }

  @Test func completionThresholdExtendsForLongMessages() {
    let renderer = BlurRevealRenderer(elapsedTime: 0)

    let threshold = renderer.completionThreshold(forCharacterCount: 900)

    #expect(threshold > 10)
    #expect(threshold == Double(899) * 0.012 + 0.3)
  }
}

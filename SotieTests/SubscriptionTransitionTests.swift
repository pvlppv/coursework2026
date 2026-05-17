import Foundation
import Testing

@testable import Sotie

struct SubscriptionTransitionTests {

  @Test func freeToTrialEmitsTrialStarted() throws {
    let events = SubscriptionTransitionTracker.events(
      from: .free,
      to: .trial(expiresAt: Date(timeIntervalSince1970: 1_000)),
      productId: PremiumProduct.annual.rawValue
    )

    #expect(events == [.trialStarted(productId: PremiumProduct.annual.rawValue)])
  }

  @Test func trialToPremiumEmitsTrialConverted() throws {
    let events = SubscriptionTransitionTracker.events(
      from: .trial(expiresAt: Date(timeIntervalSince1970: 1_000)),
      to: .premium,
      productId: PremiumProduct.annual.rawValue
    )

    #expect(events == [.trialConverted(productId: PremiumProduct.annual.rawValue)])
  }

  @Test func trialToFreeEmitsSubscriptionExpired() throws {
    let events = SubscriptionTransitionTracker.events(
      from: .trial(expiresAt: Date(timeIntervalSince1970: 1_000)),
      to: .free,
      productId: PremiumProduct.annual.rawValue
    )

    #expect(events == [.subscriptionExpired(productId: PremiumProduct.annual.rawValue)])
  }
}

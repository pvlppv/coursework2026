import Foundation
import StoreKitTest
import Testing

@testable import Sotie

@MainActor
@Suite(.serialized)
struct StoreKitSubscriptionFlowTests {

  @Test func annualSubscriptionLifecycleAndRestoreFlow() async throws {
    let manager = PremiumManager.shared
    let session = try makeSession()

    manager.resetAllData()
    session.clearTransactions()

    try await session.buyProduct(identifier: PremiumProduct.annual.rawValue)
    await manager.loadSubscriptionStatus()

    if case .trial = manager.subscriptionStatus {
      // Expected state.
    } else {
      Issue.record("Expected trial status after annual introductory purchase, got \(String(describing: manager.subscriptionStatus))")
    }

    try await manager.restorePurchases()

    switch manager.subscriptionStatus {
    case .trial, .premium:
      break
    case .free:
      Issue.record("Expected restorePurchases() to recover an active annual subscription.")
    }

    try session.forceRenewalOfSubscription(productIdentifier: PremiumProduct.annual.rawValue)
    await manager.loadSubscriptionStatus()
    #expect(manager.subscriptionStatus == .premium)

    try session.expireSubscription(productIdentifier: PremiumProduct.annual.rawValue)
    await manager.loadSubscriptionStatus()
    #expect(manager.subscriptionStatus == .free)
  }

  private func makeSession() throws -> SKTestSession {
    let storeKitConfigURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sotie.storekit")

    let session = try SKTestSession(contentsOf: storeKitConfigURL)
    session.disableDialogs = true
    session.resetToDefaultState()
    return session
  }
}

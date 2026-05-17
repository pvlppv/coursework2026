import StoreKit
import StoreKitTest
import Testing

@testable import Sotie

struct StoreKitCatalogTests {

  @Test func storeKitConfigurationMatchesPaywallOfferStrategy() async throws {
    let storeKitConfigURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sotie.storekit")

    let session = try SKTestSession(contentsOf: storeKitConfigURL)
    session.disableDialogs = true
    session.clearTransactions()
    session.resetToDefaultState()

    let productIds = PremiumProduct.allCases.map(\.rawValue)
    let products = try await Product.products(for: productIds)

    #expect(products.count == 3)

    let annualProduct = try #require(products.first(where: { $0.id == PremiumProduct.annual.rawValue }))
    let monthlyProduct = try #require(products.first(where: { $0.id == PremiumProduct.monthly.rawValue }))
    let discountProduct = try #require(products.first(where: { $0.id == PremiumProduct.annualDiscount.rawValue }))

    #expect(annualProduct.subscription?.introductoryOffer != nil)
    #expect(monthlyProduct.subscription?.introductoryOffer == nil)
    #expect(discountProduct.subscription?.introductoryOffer == nil)
  }
}

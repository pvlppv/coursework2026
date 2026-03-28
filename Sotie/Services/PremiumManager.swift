import Combine
import Foundation
import os
import Security
import StoreKit
import SwiftUI

/// Manages premium subscriptions, trials, and daily AI response limits
@MainActor
final class PremiumManager: ObservableObject {
  static let shared = PremiumManager()

  private struct PersistedSubscriptionSnapshot: Codable, Equatable {
    struct Attribution: Codable, Equatable {
      let source: String
      let variantId: String
      let eligibleForTrial: Bool
      let selectedProductId: String

      init(context: PaywallAnalyticsContext) {
        self.source = context.source.rawValue
        self.variantId = context.variantId
        self.eligibleForTrial = context.eligibleForTrial
        self.selectedProductId = context.selectedProductId
      }

      var paywallContext: PaywallAnalyticsContext {
        PaywallAnalyticsContext(
          source: PaywallSource(rawValue: source),
          variantId: variantId,
          eligibleForTrial: eligibleForTrial,
          selectedProductId: selectedProductId
        )
      }
    }

    enum State: String, Codable {
      case free
      case trial
      case premium
    }

    let state: State
    let productId: String?
    let expiresAt: Date?
    let attribution: Attribution?

    init(status: SubscriptionStatus, productId: String?, attribution: Attribution? = nil) {
      switch status {
      case .free:
        self.state = .free
        self.expiresAt = nil
      case .trial(let expiresAt):
        self.state = .trial
        self.expiresAt = expiresAt
      case .premium:
        self.state = .premium
        self.expiresAt = nil
      }
      self.productId = productId
      self.attribution = attribution
    }

    var subscriptionStatus: SubscriptionStatus {
      switch state {
      case .free:
        return .free
      case .trial:
        return .trial(expiresAt: expiresAt ?? .distantFuture)
      case .premium:
        return .premium
      }
    }
  }

  // MARK: - Published Properties

  @Published private(set) var subscriptionStatus: SubscriptionStatus = .free
  @Published private(set) var products: [Product] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isEligibleForIntroOffer = false

  // MARK: - Onboarding AI Demo Flag

  /// Tracks whether the user has consumed their one-time free AI demo during onboarding.
  /// Stored in UserDefaults so it persists across app launches.
  @AppStorage("hasConsumedOnboardingAIDemo") private(set) var hasConsumedOnboardingAIDemo = false

  /// Call after the free AI demo rounds are exhausted in onboarding to prevent replay abuse.
  func markOnboardingAIDemoConsumed() {
    hasConsumedOnboardingAIDemo = true
  }

  #if DEBUG
  /// Reset the onboarding demo flag for testing purposes.
  func resetOnboardingAIDemo() {
    hasConsumedOnboardingAIDemo = false
  }
  #endif

  // MARK: - Storage Keys

  private enum StorageKey {
    static let usageRecord = "premium_ai_usage_record"
    static let subscriptionSnapshot = "premium_subscription_snapshot"
  }

  // MARK: - Properties

  private var updateListenerTask: Task<Void, Never>?
  private let secureStore: SecureValueStore
  private let rateLimitPolicy = AIRateLimitPolicy.default
  private var cachedUsageRecord: AIUsageRecord?

  private init(secureStore: SecureValueStore? = nil) {
    self.secureStore = secureStore ?? KeychainService.usage

    // Start listening for transaction updates
    updateListenerTask = listenForTransactions()

    // Load initial subscription status
    Task {
      await loadSubscriptionStatus()
      await loadProducts()
    }
  }

  deinit {
    updateListenerTask?.cancel()
  }

  // MARK: - Product Loading

  func loadProducts() async {
    isLoading = true
    defer { isLoading = false }

    do {
      let productIds = PremiumProduct.allCases.map { $0.rawValue }
      let loadedProducts = try await Product.products(for: productIds)

      // Sort products: annual first (preselected on paywall), then monthly
      self.products = loadedProducts.sorted { $0.id.contains("annual") && !$1.id.contains("annual") }

      AppLogger.premium.info("Loaded \(self.products.count) products: \(self.products.map { $0.id })")

      // Check intro offer eligibility after products are loaded
      await checkIntroOfferEligibility()
    } catch {
      AppLogger.premium.error("Failed to load products: \(error)")
    }
  }

  // MARK: - Subscription Status

  func loadSubscriptionStatus(analyticsContext: PaywallAnalyticsContext? = nil) async {
    #if DEBUG
      if UITestOverrides.current.forcePremiumEntitlement {
        applySubscriptionSnapshot(
          PersistedSubscriptionSnapshot(status: .premium, productId: "ui-test-premium"),
          analyticsContext: analyticsContext
        )
        return
      }
    #endif

    let snapshot = await resolveCurrentSubscriptionSnapshot()
    applySubscriptionSnapshot(snapshot, analyticsContext: analyticsContext)
  }

  // MARK: - Intro Offer Eligibility

  /// Checks real intro offer eligibility via StoreKit 2.
  /// Updates the published `isEligibleForIntroOffer` property.
  func checkIntroOfferEligibility() async {
    for product in products {
      if let subscription = product.subscription,
        await subscription.isEligibleForIntroOffer
      {
        isEligibleForIntroOffer = true
        return
      }
    }
    isEligibleForIntroOffer = false
  }

  // MARK: - Purchase & Restore

  func purchase(_ product: Product, context: PaywallAnalyticsContext) async throws {
    isLoading = true
    defer { isLoading = false }

    do {
      Analytics.purchaseStarted(context: context)
      let result = try await product.purchase()

      switch result {
      case .success(let verification):
        // Verify the transaction
        switch verification {
        case .verified(let transaction):
          guard await verifyTransactionWithBackend(verification) else {
            throw PremiumError.purchaseFailed
          }
          // Grant access
          await transaction.finish()
          await loadSubscriptionStatus(analyticsContext: context)

          // Cancel nudge campaign if user just subscribed
          if subscriptionStatus.isPremium {
            NotificationScheduler.shared.cancelOnboardingResumeNudges()
            Analytics.onboardingResumeCancelled(reason: "purchase")
          }

          AppLogger.premium.info("Purchase successful: \(transaction.productID)")
          Analytics.purchaseCompleted(context: context)

        case .unverified:
          throw PremiumError.purchaseFailed
        }

      case .userCancelled:
        throw PremiumError.purchaseCancelled

      case .pending:
        // Purchase is pending (e.g., Ask to Buy)
        AppLogger.premium.info("Purchase pending")

      @unknown default:
        throw PremiumError.purchaseFailed
      }
    } catch {
      if let premiumError = error as? PremiumError {
        throw premiumError
      }
      throw PremiumError.purchaseFailed
    }
  }

  func restorePurchases() async throws {
    isLoading = true
    defer { isLoading = false }

    // Sync with App Store — let network/auth errors propagate with Apple's descriptions
    try await AppStore.sync()
    await loadSubscriptionStatus()

    // Cancel nudge campaign if restore succeeded
    if subscriptionStatus.isPremium {
      NotificationScheduler.shared.cancelOnboardingResumeNudges()
      Analytics.onboardingResumeCancelled(reason: "restore")
    }

    // Successful sync, but no active subscriptions found
    if subscriptionStatus == .free {
      throw PremiumError.restoreFailed
    }

    AppLogger.premium.info("Purchases restored")
  }

  // MARK: - Transaction Listener

  private func listenForTransactions() -> Task<Void, Never> {
    return Task {
      for await result in Transaction.updates {
        if case .verified(let transaction) = result {
          guard await self.verifyTransactionWithBackend(result) else { continue }
          await transaction.finish()
          await self.loadSubscriptionStatus()

          // Cancel nudge campaign on background subscription update
          if self.subscriptionStatus.isPremium {
            NotificationScheduler.shared.cancelOnboardingResumeNudges()
            Analytics.onboardingResumeCancelled(reason: "transaction_update")
          }

          AppLogger.premium.info("Transaction updated: \(transaction.productID)")
        }
      }
    }
  }

  /// Call this when app becomes active to check for subscription changes
  func refreshSubscriptionStatus() {
    Task {
      await loadSubscriptionStatus()
    }
  }

  // MARK: - Daily AI Response Limits

  func canRequestAIResponse(forEntryId entryId: String? = nil) -> Bool {
    if !subscriptionStatus.isPremium {
      // Free users: allow AI calls only while onboarding demo hasn't been consumed.
      return !hasConsumedOnboardingAIDemo
    }

    // Premium users: 200 responses/day hard limit
    let stats = getAIResponseUsageStats()
    return stats.canRequestAIResponse
  }

  func recordAIResponse() {
    var record = loadUsageRecord()
    record.recordAIResponse(at: Date(), calendar: .current)
    saveUsageRecord(record)

    #if DEBUG
      let stats = getAIResponseUsageStats()
      AppLogger.premium.info("AI response recorded: \(stats.responsesToday)/\(stats.maxResponsesPerDay)")
    #endif
  }

  func getAIResponseUsageStats() -> AIResponseUsageStats {
    let isPremium = subscriptionStatus.isPremium
    let record = loadUsageRecord()

    return AIResponseUsageStats(
      responsesToday: record.responsesToday,
      maxResponsesPerDay: rateLimitPolicy.maxResponsesPerDay,
      isPremium: isPremium
    )
  }

  func reserveRequestSlot() throws {
    var record = loadUsageRecord()
    let runtimeState = SecurityManager.shared.currentRuntimeState()

    do {
      try record.reserveRequestSlot(
        at: Date(),
        policy: rateLimitPolicy,
        isSuspiciousEnvironment: runtimeState.isSuspiciousEnvironment
      )
      saveUsageRecord(record)
    } catch let error as AIRequestThrottleError {
      switch error {
      case .perMinuteLimitExceeded(let retryAfter):
        SecurityManager.shared.recordEvent(
          .requestBurstRejected,
          detail: String(format: "%.2f", retryAfter)
        )
        throw PremiumError.requestRateLimited(retryAfter: retryAfter)
      case .dailyLimitExceeded:
        throw PremiumError.responseLimitReached
      }
    }
  }

  private func loadUsageRecord(now: Date = Date(), calendar: Calendar = .current) -> AIUsageRecord {
    let currentFingerprint = SecurityManager.shared.deviceFingerprint()

    // Use in-memory cache to avoid Keychain I/O on every read
    let storedRecord = cachedUsageRecord
      ?? (try? secureStore.codable(AIUsageRecord.self, for: StorageKey.usageRecord))
      ?? AIUsageRecord(dayAnchor: now, deviceFingerprint: currentFingerprint)

    var normalizedRecord = storedRecord
    normalizedRecord.normalize(now: now, calendar: calendar)

    if normalizedRecord.deviceFingerprint != currentFingerprint {
      normalizedRecord.deviceFingerprint = currentFingerprint
      SecurityManager.shared.recordEvent(
        .deviceFingerprintChanged,
        detail: "Usage record fingerprint refreshed."
      )
    }

    if normalizedRecord != storedRecord {
      saveUsageRecord(normalizedRecord)
    }

    cachedUsageRecord = normalizedRecord
    return normalizedRecord
  }

  private func saveUsageRecord(_ record: AIUsageRecord) {
    cachedUsageRecord = record
    do {
      try secureStore.setCodable(
        record,
        for: StorageKey.usageRecord,
        accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      )
    } catch {
      SecurityManager.shared.recordEvent(
        .keychainFailure,
        detail: "Failed to save AI usage record: \(error.localizedDescription)"
      )
    }
  }

  private func resolveCurrentSubscriptionSnapshot() async -> PersistedSubscriptionSnapshot {
    if let backendSnapshot = await resolveBackendSubscriptionSnapshot() {
      return backendSnapshot
    }

    var activeProductId: String?
    var activeStatus: SubscriptionStatus = .free

    for await result in Transaction.currentEntitlements {
      if case .verified(let transaction) = result {
        guard await verifyTransactionWithBackend(result) else { continue }
        if transaction.productType == .autoRenewable && !transaction.isUpgraded {
          activeProductId = transaction.productID

          if transaction.offer?.type == .introductory, let trialEnd = transaction.expirationDate {
            activeStatus = .trial(expiresAt: trialEnd)
          } else {
            activeStatus = .premium
          }

          break
        }
      }
    }

    return PersistedSubscriptionSnapshot(status: activeStatus, productId: activeProductId)
  }

  private func resolveBackendSubscriptionSnapshot() async -> PersistedSubscriptionSnapshot? {
    guard BackendConfig.isEnabled else { return nil }

    do {
      let session = try await BackendClient.shared.ensureSession()
      guard let status = session.entitlement.subscriptionStatus else { return nil }
      return PersistedSubscriptionSnapshot(status: status, productId: session.entitlement.productId)
    } catch {
      AppLogger.premium.error("Backend entitlement sync failed: \(error.localizedDescription)")
      return nil
    }
  }

  private func verifyTransactionWithBackend(_ verification: VerificationResult<StoreKit.Transaction>) async -> Bool {
    guard BackendConfig.isEnabled else { return true }
    guard case .verified(let transaction) = verification else { return false }
    guard PremiumProduct(rawValue: transaction.productID) != nil else {
      AppLogger.premium.error("Ignoring unknown StoreKit product: \(transaction.productID)")
      return false
    }

    do {
      _ = try await BackendClient.shared.verifyTransaction(signedTransactionInfo: verification.jwsRepresentation)
      return true
    } catch {
      AppLogger.premium.error("Backend StoreKit verification failed: \(error.localizedDescription)")
      return false
    }
  }

  private func applySubscriptionSnapshot(
    _ newSnapshot: PersistedSubscriptionSnapshot,
    analyticsContext: PaywallAnalyticsContext? = nil
  ) {
    let previousSnapshot = loadPersistedSubscriptionSnapshot()
    let lifecycleContext = analyticsContext ?? previousSnapshot?.attribution?.paywallContext
    let persistedAttribution: PersistedSubscriptionSnapshot.Attribution?

    switch newSnapshot.subscriptionStatus {
    case .free:
      persistedAttribution = nil
    case .trial, .premium:
      persistedAttribution = lifecycleContext.map(PersistedSubscriptionSnapshot.Attribution.init)
    }

    let snapshotToPersist = PersistedSubscriptionSnapshot(
      status: newSnapshot.subscriptionStatus,
      productId: newSnapshot.productId,
      attribution: persistedAttribution
    )
    subscriptionStatus = newSnapshot.subscriptionStatus

    switch newSnapshot.subscriptionStatus {
    case .trial(let trialEnd):
      AppLogger.premium.info("User is in trial period until \(trialEnd)")
    case .premium:
      AppLogger.premium.info("User has active premium subscription")
    case .free:
      AppLogger.premium.info("User is on free tier")
    }

    if let previousSnapshot {
      let productId = newSnapshot.productId ?? previousSnapshot.productId

      if let productId {
        for event in SubscriptionTransitionTracker.events(
          from: previousSnapshot.subscriptionStatus,
          to: newSnapshot.subscriptionStatus,
          productId: productId
        ) {
          sendLifecycleAnalytics(event, context: lifecycleContext)
        }
      }
    }

    savePersistedSubscriptionSnapshot(snapshotToPersist)
  }

  private func loadPersistedSubscriptionSnapshot() -> PersistedSubscriptionSnapshot? {
    guard
      let data = UserDefaults.standard.data(forKey: StorageKey.subscriptionSnapshot),
      let snapshot = try? JSONDecoder().decode(PersistedSubscriptionSnapshot.self, from: data)
    else {
      return nil
    }

    return snapshot
  }

  private func savePersistedSubscriptionSnapshot(_ snapshot: PersistedSubscriptionSnapshot) {
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    UserDefaults.standard.set(data, forKey: StorageKey.subscriptionSnapshot)
  }

  private func sendLifecycleAnalytics(
    _ event: SubscriptionLifecycleEvent,
    context: PaywallAnalyticsContext?
  ) {
    switch event {
    case .trialStarted(let productId):
      Analytics.trialStarted(productId: productId, context: context)
    case .trialConverted(let productId):
      Analytics.trialConverted(productId: productId, context: context)
    case .subscriptionExpired(let productId):
      Analytics.subscriptionExpired(productId: productId, context: context)
    }
  }

  // MARK: - Debug Helpers

  #if DEBUG
    func resetAllData() {
      cachedUsageRecord = nil
      try? secureStore.removeValue(for: StorageKey.usageRecord)
      UserDefaults.standard.removeObject(forKey: StorageKey.subscriptionSnapshot)

      Task {
        await loadSubscriptionStatus()
      }

      AppLogger.premium.info("Premium data reset")
    }

    func resetDailyResponses() {
      cachedUsageRecord = nil
      try? secureStore.removeValue(for: StorageKey.usageRecord)
      AppLogger.premium.info("Daily AI responses reset")
    }
  #endif
}

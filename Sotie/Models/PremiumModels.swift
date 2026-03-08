import Foundation

// MARK: - Subscription Status

enum SubscriptionStatus: Equatable {
  case free
  case trial(expiresAt: Date)
  case premium

  var isPremium: Bool {
    switch self {
    case .trial, .premium:
      return true
    case .free:
      return false
    }
  }

  var displayName: String {
    switch self {
    case .free:
      return appLocalizedString(Localizable.premiumStatusFree)
    case .trial, .premium:
      return appLocalizedString(Localizable.premiumStatusPremium)
    }
  }
}

// MARK: - Product Identifiers

enum PremiumProduct: String, CaseIterable {
  case monthly = "com.pvlppv.sotie.journal.premium.monthly"
  case annual = "com.pvlppv.sotie.journal.premium.annual"
  /// 50% off variant of `annual`. Sold exclusively through the
  /// onboarding squeeze paywall (`DiscountPaywallView`). Identical
  /// entitlements as `annual` — `PremiumManager` treats it the same
  /// way once unlocked.
  case annualDiscount = "com.pvlppv.sotie.journal.premium.annual.discount"

  var displayName: String {
    switch self {
    case .monthly:
      return appLocalizedString(Localizable.premiumMonthly)
    case .annual, .annualDiscount:
      return appLocalizedString(Localizable.premiumAnnual)
    }
  }
}

// MARK: - AI Response Usage Stats

struct AIResponseUsageStats {
  let responsesToday: Int
  let maxResponsesPerDay: Int
  let isPremium: Bool

  var canRequestAIResponse: Bool {
    responsesToday < maxResponsesPerDay
  }

  var responsesRemaining: Int {
    max(0, maxResponsesPerDay - responsesToday)
  }

  var displayText: String {
    if isPremium {
      return
        "\(responsesToday)/\(maxResponsesPerDay) \(appLocalizedString(Localizable.premiumAIResponsesToday))"
    } else {
      return appLocalizedString(Localizable.premiumSubscribeToUnlock)
    }
  }
}

struct AIRateLimitPolicy: Equatable, Sendable {
  let maxResponsesPerDay: Int
  let maxRequestsPerMinute: Int
  /// Stricter per-minute cap for jailbroken devices.
  let suspiciousMaxRequestsPerMinute: Int

  static let `default` = AIRateLimitPolicy(
    maxResponsesPerDay: 200,
    maxRequestsPerMinute: 40,
    suspiciousMaxRequestsPerMinute: 8
  )

  func requestsPerMinuteLimit(isSuspiciousEnvironment: Bool) -> Int {
    isSuspiciousEnvironment ? suspiciousMaxRequestsPerMinute : maxRequestsPerMinute
  }
}



enum AIRequestThrottleError: LocalizedError, Equatable {
  case perMinuteLimitExceeded(retryAfter: TimeInterval)
  case dailyLimitExceeded

  var errorDescription: String? {
    switch self {
    case .perMinuteLimitExceeded(let retryAfter):
      return "AI request burst limit reached. Retry in \(Int(retryAfter.rounded(.up))) seconds."
    case .dailyLimitExceeded:
      return "Daily AI response limit reached."
    }
  }
}

struct AIUsageRecord: Codable, Equatable, Sendable {
  var dayAnchor: Date
  var responsesToday: Int
  var reservedRequestDates: [Date]
  var deviceFingerprint: String

  init(
    dayAnchor: Date = Date(),
    responsesToday: Int = 0,
    reservedRequestDates: [Date] = [],
    deviceFingerprint: String
  ) {
    self.dayAnchor = dayAnchor
    self.responsesToday = responsesToday
    self.reservedRequestDates = reservedRequestDates
    self.deviceFingerprint = deviceFingerprint
  }

  mutating func normalize(now: Date, calendar: Calendar) {
    if !calendar.isDate(dayAnchor, inSameDayAs: now) {
      dayAnchor = now
      responsesToday = 0
      reservedRequestDates = []
      return
    }

    reservedRequestDates = reservedRequestDates.filter { $0 >= now.addingTimeInterval(-60) }
  }

  mutating func recordAIResponse(at now: Date, calendar: Calendar) {
    normalize(now: now, calendar: calendar)
    responsesToday += 1
  }

  mutating func reserveRequestSlot(
    at now: Date,
    policy: AIRateLimitPolicy,
    isSuspiciousEnvironment: Bool,
    calendar: Calendar = .current
  ) throws {
    normalize(now: now, calendar: calendar)

    // Daily cap — applies to all callers, not just UI flow
    if responsesToday >= policy.maxResponsesPerDay {
      throw AIRequestThrottleError.dailyLimitExceeded
    }

    let maxPerMinute = policy.requestsPerMinuteLimit(isSuspiciousEnvironment: isSuspiciousEnvironment)

    if reservedRequestDates.count >= maxPerMinute {
      let retryAfter = max(
        0,
        (reservedRequestDates.first?.addingTimeInterval(60) ?? now).timeIntervalSince(now)
      )
      throw AIRequestThrottleError.perMinuteLimitExceeded(retryAfter: retryAfter)
    }

    reservedRequestDates.append(now)
  }
}

// MARK: - Purchase Error

enum PremiumError: LocalizedError {
  case purchaseFailed
  case purchaseCancelled
  case restoreFailed
  case productNotFound
  case responseLimitReached
  case requestRateLimited(retryAfter: TimeInterval)

  var errorDescription: String? {
    switch self {
    case .purchaseFailed:
      return appLocalizedString(Localizable.premiumErrorPurchaseFailed)
    case .purchaseCancelled:
      return appLocalizedString(Localizable.premiumErrorCancelled)
    case .restoreFailed:
      return appLocalizedString(Localizable.premiumErrorRestoreFailed)
    case .productNotFound:
      return appLocalizedString(Localizable.premiumErrorProductNotFound)
    case .responseLimitReached:
      return appLocalizedString(Localizable.errorDailyLimitReached)
    case .requestRateLimited(let retryAfter):
      return appLocalizedString(Localizable.errorRateLimited, arguments: Int(retryAfter.rounded(.up)))
    }
  }
}

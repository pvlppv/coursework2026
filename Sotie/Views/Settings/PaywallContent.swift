import Foundation

nonisolated enum PaywallVariant: String, Sendable {
  case reviewSafeBaseline = "paywall_v1_review_safe"
}

nonisolated enum PaywallSource: Equatable, Sendable {
  case onboardingCheckpoint
  case responseLimitReached
  case settings
  case generic
  case custom(String)

  init(rawValue: String) {
    switch rawValue {
    case "onboarding_checkpoint":
      self = .onboardingCheckpoint
    case "response_limit_reached":
      self = .responseLimitReached
    case "settings":
      self = .settings
    case "", "paywall":
      self = .generic
    default:
      self = .custom(rawValue)
    }
  }

  var rawValue: String {
    switch self {
    case .onboardingCheckpoint:
      return "onboarding_checkpoint"
    case .responseLimitReached:
      return "response_limit_reached"
    case .settings:
      return "settings"
    case .generic:
      return "paywall"
    case .custom(let value):
      return value
    }
  }
}

nonisolated enum PaywallPlanKind: Sendable, Equatable {
  case monthly
  case annual
}

nonisolated struct PaywallPlanDescriptor: Equatable, Sendable {
  let id: String
  let kind: PaywallPlanKind
  let displayName: String
  let displayPrice: String
  let fullBillingDescription: String
  let monthlyEquivalentDescription: String?
  let savingsDescription: String?
  let hasIntroOffer: Bool
}

nonisolated struct PaywallHeroContent: Equatable, Sendable {
  let title: String
  let subtitle: String
}

nonisolated struct PaywallValueCard: Equatable, Sendable {
  let icon: String
  let title: String
}

nonisolated struct PaywallJourneyStep: Equatable, Sendable {
  let timeLabel: String
  let description: String
}

nonisolated struct PaywallTimelineStep: Equatable, Sendable {
  let icon: String
  let title: String
  let detail: String
}

nonisolated struct PaywallContentState: Equatable, Sendable {
  let source: PaywallSource
  let variantId: String
  let hero: PaywallHeroContent
  let valueCards: [PaywallValueCard]
  let journeyTimeline: [PaywallJourneyStep]
  let trialTimeline: [PaywallTimelineStep]
  let selectedPlan: PaywallPlanDescriptor?
  let primaryCTA: String

  var showsTrialTimeline: Bool {
    !trialTimeline.isEmpty
  }
}

@MainActor
enum PaywallContentFactory {
  static func make(
    source: PaywallSource,
    variantId: String,
    isEligibleForIntroOffer: Bool,
    selectedPlanId: String,
    plans: [PaywallPlanDescriptor]
  ) -> PaywallContentState {
    let selectedPlan = preferredPlan(selectedPlanId: selectedPlanId, plans: plans)
    let hasEligibleAnnualTrial = isEligibleForIntroOffer
      && plans.contains(where: { $0.kind == .annual && $0.hasIntroOffer })

    return PaywallContentState(
      source: source,
      variantId: variantId,
      hero: hero(for: source),
      valueCards: valueCards(),
      journeyTimeline: journeySteps(),
      trialTimeline: hasEligibleAnnualTrial ? timeline() : [],
      selectedPlan: selectedPlan,
      primaryCTA: ctaText(for: selectedPlan, isEligibleForIntroOffer: isEligibleForIntroOffer)
    )
  }

  static func preferredPlan(selectedPlanId: String, plans: [PaywallPlanDescriptor]) -> PaywallPlanDescriptor? {
    if let selectedPlan = plans.first(where: { $0.id == selectedPlanId }) {
      return selectedPlan
    }

    if let annual = plans.first(where: { $0.kind == .annual }) {
      return annual
    }

    return plans.first
  }

  private static func hero(for source: PaywallSource) -> PaywallHeroContent {
    switch source {
    case .onboardingCheckpoint:
      return PaywallHeroContent(
        title: appLocalizedString(Localizable.premiumHeroOnboardingTitle),
        subtitle: appLocalizedString(Localizable.premiumHeroOnboardingSubtitleTrial)
      )
    case .responseLimitReached:
      return PaywallHeroContent(
        title: appLocalizedString(Localizable.premiumHeroLimitTitle),
        subtitle: appLocalizedString(Localizable.premiumHeroLimitSubtitleTrial)
      )
    case .settings:
      return PaywallHeroContent(
        title: appLocalizedString(Localizable.premiumHeroSettingsTitle),
        subtitle: appLocalizedString(Localizable.premiumHeroSettingsSubtitleTrial)
      )
    case .generic, .custom:
      return PaywallHeroContent(
        title: appLocalizedString(Localizable.premiumHeroDefaultTitle),
        subtitle: appLocalizedString(Localizable.premiumHeroDefaultSubtitleTrial)
      )
    }
  }

  private static func valueCards() -> [PaywallValueCard] {
    [
      PaywallValueCard(
        icon: "infinity",
        title: appLocalizedString(Localizable.premiumBenefit1)
      ),
      PaywallValueCard(
        icon: "waveform.path.ecg.text.page",
        title: appLocalizedString(Localizable.premiumBenefit2)
      ),
      PaywallValueCard(
        icon: "arrow.triangle.branch",
        title: appLocalizedString(Localizable.premiumBenefit3)
      ),
    ]
  }

  private static func journeySteps() -> [PaywallJourneyStep] {
    [
      PaywallJourneyStep(
        timeLabel: appLocalizedString(Localizable.premiumJourneyTime1),
        description: appLocalizedString(Localizable.premiumJourneyStep1)
      ),
      PaywallJourneyStep(
        timeLabel: appLocalizedString(Localizable.premiumJourneyTime2),
        description: appLocalizedString(Localizable.premiumJourneyStep2)
      ),
      PaywallJourneyStep(
        timeLabel: appLocalizedString(Localizable.premiumJourneyTime3),
        description: appLocalizedString(Localizable.premiumJourneyStep3)
      ),
    ]
  }

  private static func timeline() -> [PaywallTimelineStep] {
    [
      PaywallTimelineStep(
        icon: "sparkles",
        title: appLocalizedString(Localizable.premiumTimelineToday),
        detail: appLocalizedString(Localizable.premiumTimelineTodayDetail)
      ),
      PaywallTimelineStep(
        icon: "bell",
        title: appLocalizedString(Localizable.premiumTimelineDay3),
        detail: appLocalizedString(Localizable.premiumTimelineDay3Detail)
      ),
      PaywallTimelineStep(
        icon: "creditcard",
        title: appLocalizedString(Localizable.premiumTimelineDay7),
        detail: appLocalizedString(Localizable.premiumTimelineDay7Detail)
      ),
    ]
  }

  private static func ctaText(
    for plan: PaywallPlanDescriptor?,
    isEligibleForIntroOffer: Bool
  ) -> String {
    guard let plan else {
      return appLocalizedString(Localizable.premiumSubscribe)
    }

    if plan.kind == .annual, plan.hasIntroOffer, isEligibleForIntroOffer {
      return appLocalizedString(Localizable.premiumTrySevenDaysFree)
    }

    switch plan.kind {
    case .annual:
      return appLocalizedString(Localizable.premiumContinueAnnual)
    case .monthly:
      return appLocalizedString(Localizable.premiumSubscribeMonthly)
    }
  }
}

nonisolated struct PaywallAnalyticsContext: Equatable, Sendable {
  let source: PaywallSource
  let variantId: String
  let eligibleForTrial: Bool
  let selectedProductId: String

  var parameters: [String: String] {
    [
      "source": source.rawValue,
      "variantId": variantId,
      "eligibleForTrial": String(eligibleForTrial),
      "selectedProductId": selectedProductId,
    ]
  }
}

nonisolated enum SubscriptionLifecycleEvent: Equatable, Sendable {
  case trialStarted(productId: String)
  case trialConverted(productId: String)
  case subscriptionExpired(productId: String)
}

nonisolated enum SubscriptionTransitionTracker {
  static func events(
    from oldStatus: SubscriptionStatus,
    to newStatus: SubscriptionStatus,
    productId: String
  ) -> [SubscriptionLifecycleEvent] {
    switch (oldStatus, newStatus) {
    case (.free, .trial):
      return [.trialStarted(productId: productId)]
    case (.trial, .premium):
      return [.trialConverted(productId: productId)]
    case (.trial, .free), (.premium, .free):
      return [.subscriptionExpired(productId: productId)]
    default:
      return []
    }
  }
}

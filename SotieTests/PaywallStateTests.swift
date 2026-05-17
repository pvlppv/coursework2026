import Foundation
import Testing

@testable import Sotie

@MainActor
struct PaywallStateTests {

  @Test func eligibleAnnualPlanShowsTrialTimelineAndTrialCTA() throws {
    let monthlyPlan = PaywallPlanDescriptor(
      id: PremiumProduct.monthly.rawValue,
      kind: .monthly,
      displayName: "Monthly",
      displayPrice: "$8.99",
      fullBillingDescription: "$8.99/month",
      monthlyEquivalentDescription: nil,
      savingsDescription: nil,
      hasIntroOffer: false
    )
    let annualPlan = PaywallPlanDescriptor(
      id: PremiumProduct.annual.rawValue,
      kind: .annual,
      displayName: "Annual",
      displayPrice: "$68.99",
      fullBillingDescription: "$68.99/year",
      monthlyEquivalentDescription: "Just $5.75/mo",
      savingsDescription: "Save 36%",
      hasIntroOffer: true
    )

    let state = PaywallContentFactory.make(
      source: .onboardingCheckpoint,
      variantId: PaywallVariant.reviewSafeBaseline.rawValue,
      isEligibleForIntroOffer: true,
      selectedPlanId: annualPlan.id,
      plans: [annualPlan, monthlyPlan]
    )

    #expect(state.hero.title == "Keep going while it's still clear")
    #expect(state.primaryCTA == "Try 7 Days Free")
    #expect(state.showsTrialTimeline)
    #expect(state.hero.subtitle == "Unlock uninterrupted reflection and full premium access.")
    #expect(state.trialTimeline.map(\.title) == ["Today", "Day 6", "Day 7"])
  }

  @Test func ineligibleAnnualPlanHidesTrialTimelineAndUsesAnnualCTA() throws {
    let annualPlan = PaywallPlanDescriptor(
      id: PremiumProduct.annual.rawValue,
      kind: .annual,
      displayName: "Annual",
      displayPrice: "$68.99",
      fullBillingDescription: "$68.99/year",
      monthlyEquivalentDescription: "Just $5.75/mo",
      savingsDescription: "Save 36%",
      hasIntroOffer: true
    )

    let state = PaywallContentFactory.make(
      source: .responseLimitReached,
      variantId: PaywallVariant.reviewSafeBaseline.rawValue,
      isEligibleForIntroOffer: false,
      selectedPlanId: annualPlan.id,
      plans: [annualPlan]
    )

    #expect(state.hero.title == "Don't stop at the important part")
    #expect(state.primaryCTA == "Continue with Annual")
    #expect(!state.showsTrialTimeline)
    #expect(state.trialTimeline.isEmpty)
    #expect(state.hero.subtitle == "Continue this reflection without limits.")
  }

  @Test func monthlyPlanNeverShowsTrialTimelineAndUsesMonthlyCTA() throws {
    let monthlyPlan = PaywallPlanDescriptor(
      id: PremiumProduct.monthly.rawValue,
      kind: .monthly,
      displayName: "Monthly",
      displayPrice: "$8.99",
      fullBillingDescription: "$8.99/month",
      monthlyEquivalentDescription: nil,
      savingsDescription: nil,
      hasIntroOffer: false
    )
    let annualPlan = PaywallPlanDescriptor(
      id: PremiumProduct.annual.rawValue,
      kind: .annual,
      displayName: "Annual",
      displayPrice: "$68.99",
      fullBillingDescription: "$68.99/year",
      monthlyEquivalentDescription: "Just $5.75/mo",
      savingsDescription: "Save 36%",
      hasIntroOffer: true
    )

    let state = PaywallContentFactory.make(
      source: .settings,
      variantId: PaywallVariant.reviewSafeBaseline.rawValue,
      isEligibleForIntroOffer: true,
      selectedPlanId: monthlyPlan.id,
      plans: [annualPlan, monthlyPlan]
    )

    #expect(state.hero.title == "Unlock deeper reflection")
    #expect(state.primaryCTA == "Subscribe Monthly")
    #expect(state.showsTrialTimeline)
    #expect(state.trialTimeline.map(\.title) == ["Today", "Day 6", "Day 7"])
    #expect(state.hero.subtitle == "Use Sotie without limits and see patterns over time.")
  }
}

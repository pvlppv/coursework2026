//
//  PaywallView.swift
//  Sotie
//
//  Redesigned on 24.03.2026.
//

import StoreKit
import SwiftUI

// MARK: - Timeline Preference Key

private struct TimelineDotAnchors: PreferenceKey {
  static var defaultValue: [Int: Anchor<CGPoint>] = [:]
  static func reduce(value: inout [Int: Anchor<CGPoint>], nextValue: () -> [Int: Anchor<CGPoint>]) {
    value.merge(nextValue(), uniquingKeysWith: { $1 })
  }
}

struct PaywallView: View {
  var source: PaywallSource = .generic
  var variantId: String = PaywallVariant.reviewSafeBaseline.rawValue
  /// When true, shows a delayed "Maybe later" dismiss button instead of immediate ✕.
  /// Used for the first paywall presentation from onboarding.
  var isFirstPresentation: Bool = false

  /// Optional close handler for non-modal contexts (e.g. onboarding overlay).
  /// When nil, uses standard `dismiss()` (sheet/fullScreenCover).
  var onClose: (() -> Void)? = nil

  /// Hides the toolbar close / "Maybe later" button entirely.
  /// Used for the onboarding hard-paywall step where the only ways out
  /// are a successful purchase or a successful restore.
  var hideCloseButton: Bool = false

  @StateObject private var premiumManager = PremiumManager.shared
  @Environment(\.dismiss) private var dismiss

  @State private var selectedProductId: String = ""
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var isPurchasing = false
  @State private var resolvedSource: PaywallSource?
  @State private var heroAppeared = false
  @State private var bulletsAppeared = false
  @State private var dockAppeared = false
  private let uiTestOverrides = UITestOverrides.current

  // Adaptive sparkle glow — monochrome system
  private var sparkleGlowInner: Color {
    Color.theme.shadow.opacity(0.12)
  }

  private var sparkleGlowOuter: Color {
    Color.theme.shadow.opacity(0.06)
  }

  private func closePaywall() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  private var activeSource: PaywallSource {
    resolvedSource ?? source
  }

  private var selectedProduct: Product? {
    if let selected = premiumManager.products.first(where: { $0.id == selectedProductId }) {
      return selected
    }
    return premiumManager.products.first(where: { $0.id == preferredProductId(from: premiumManager.products) })
  }

  private var orderedPlanDescriptors: [PaywallPlanDescriptor] {
    availablePlanDescriptors.sorted { lhs, rhs in
      switch (lhs.kind, rhs.kind) {
      case (.annual, .monthly):
        return true
      case (.monthly, .annual):
        return false
      default:
        return lhs.id < rhs.id
      }
    }
  }

  private var planDescriptors: [PaywallPlanDescriptor] {
    premiumManager.products
      .filter { $0.id != PremiumProduct.annualDiscount.rawValue }
      .compactMap(planDescriptor(for:))
  }

  private var fallbackPlanDescriptors: [PaywallPlanDescriptor] {
    guard uiTestOverrides.usesStubPaywallPlans else { return [] }

    return [
      PaywallPlanDescriptor(
        id: PremiumProduct.annual.rawValue,
        kind: .annual,
        displayName: appLocalizedString(Localizable.premiumAnnual),
        displayPrice: "$68.99",
        fullBillingDescription: "$68.99 \(appLocalizedString(Localizable.premiumBilledAnnually))",
        monthlyEquivalentDescription: appLocalizedString(Localizable.premiumMonthlyEquivalent, arguments: "$5.75"),
        savingsDescription: appLocalizedString(Localizable.premiumSavePercent, arguments: 36),
        hasIntroOffer: true
      ),
      PaywallPlanDescriptor(
        id: PremiumProduct.monthly.rawValue,
        kind: .monthly,
        displayName: appLocalizedString(Localizable.premiumMonthly),
        displayPrice: "$8.99",
        fullBillingDescription: "$8.99 \(appLocalizedString(Localizable.premiumBilledMonthly))",
        monthlyEquivalentDescription: nil,
        savingsDescription: nil,
        hasIntroOffer: false
      ),
    ]
  }

  private var availablePlanDescriptors: [PaywallPlanDescriptor] {
    planDescriptors.isEmpty ? fallbackPlanDescriptors : planDescriptors
  }

  private var resolvedTrialEligibility: Bool {
    if let forcedTrialEligibility = uiTestOverrides.forcedTrialEligibility {
      return forcedTrialEligibility
    }

    return premiumManager.isEligibleForIntroOffer || uiTestOverrides.usesStubPaywallPlans
  }

  private var contentState: PaywallContentState {
    PaywallContentFactory.make(
      source: activeSource,
      variantId: variantId,
      isEligibleForIntroOffer: resolvedTrialEligibility,
      selectedPlanId: selectedProductId,
      plans: availablePlanDescriptors
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.theme.backgroundPrimary.ignoresSafeArea()

        ScrollView(showsIndicators: false) {
          VStack(spacing: 0) {
            // MARK: - Hero
            heroSection
              .padding(.top, 8)
              .opacity(heroAppeared ? 1 : 0)
              .offset(y: heroAppeared ? 0 : 16)

            // MARK: - Benefits
            valueBulletsSection
              .padding(.top, 32)
              .opacity(bulletsAppeared ? 1 : 0)
              .offset(y: bulletsAppeared ? 0 : 12)
          }
          .padding(.horizontal, 24)
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        purchaseDock
          .opacity(dockAppeared ? 1 : 0)
          .offset(y: dockAppeared ? 0 : 20)
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          if hideCloseButton {
            EmptyView()
          } else if isFirstPresentation {
            Button {
              Analytics.paywallDismissed(context: analyticsContext())
              closePaywall()
            } label: {
              Text(appLocalizedString(Localizable.premiumMaybeLater))
                .font(.subheadline)
                .themeText(.secondary)
            }
            .accessibilityIdentifier("paywall-maybe-later")
          } else {
            Button {
              Analytics.paywallDismissed(context: analyticsContext())
              closePaywall()
            } label: {
              Image(systemName: "xmark")
                .font(.system(size: 15, weight: .medium))
                .themeText(.secondary)
            }
            .accessibilityIdentifier("paywall-close")
          }
        }
      }
      .alert(appLocalizedString(Localizable.premiumErrorPurchaseFailed), isPresented: $showError) {
        Button(appLocalizedString(Localizable.cancel), role: .cancel) {}
      } message: {
        Text(errorMessage)
      }
    }
    .onAppear {
      resolveActiveSourceIfNeeded()
      selectPreferredProductIfNeeded()

      Task {
        await premiumManager.checkIntroOfferEligibility()
      }

      Analytics.paywallViewed(context: analyticsContext())


      // Staggered entrance animations
      withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
        heroAppeared = true
      }
      withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
        bulletsAppeared = true
      }
      withAnimation(.easeOut(duration: 0.5).delay(0.35)) {
        dockAppeared = true
      }
    }
    .onChange(of: premiumManager.products) { _, _ in
      selectPreferredProductIfNeeded()
    }
  }


  // MARK: - Hero Section

  private var heroSection: some View {
    VStack(spacing: 14) {
      // Sparkle icon — premium glow (adaptive per theme)
      Image(systemName: "sparkles")
        .font(.system(size: 80, weight: .thin))
        .themeText(.primary)
        .shadow(color: sparkleGlowInner, radius: 30, x: 0, y: 0)
        .shadow(color: sparkleGlowOuter, radius: 60, x: 0, y: 0)
        .padding(.bottom, 14)

      Text(contentState.hero.title)
        .font(.system(size: 28, weight: .bold))
        .themeText(.primary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("paywall-hero-title")

      Text(contentState.hero.subtitle)
        .font(.system(size: 16))
        .themeText(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("paywall-hero-subtitle")
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - Value Bullets

  @ViewBuilder
  private var valueBulletsSection: some View {
    let steps = contentState.journeyTimeline
    let dotSize: CGFloat = 10
    let columnWidth: CGFloat = 20

    VStack(alignment: .leading, spacing: 28) {
      ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
        HStack(alignment: .top, spacing: 16) {
          // Dot — centered in column
          Circle()
            .fill(Color.theme.buttonBackground)
            .frame(width: dotSize, height: dotSize)
            .frame(width: columnWidth)
            .padding(.top, 3)
            .anchorPreference(key: TimelineDotAnchors.self, value: .center) { anchor in
              [index: anchor]
            }

          // Text
          VStack(alignment: .leading, spacing: 3) {
            Text(step.timeLabel)
              .font(.system(size: 16, weight: .bold))
              .themeText(.primary)

            Text(step.description)
              .font(.system(size: 15))
              .themeText(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

        }
      }
    }
    .backgroundPreferenceValue(TimelineDotAnchors.self) { anchors in
      GeometryReader { proxy in
        if let first = anchors[0], let last = anchors[steps.count - 1] {
          let startY = proxy[first].y
          let endY = proxy[last].y
          let centerX = proxy[first].x

          Rectangle()
            .fill(Color.theme.textTertiary.opacity(0.5))
            .frame(width: 1.5, height: endY - startY)
            .position(x: centerX, y: (startY + endY) / 2)
        }
      }
      .allowsHitTesting(false)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }


  // MARK: - Purchase Dock

  private var purchaseDock: some View {
    VStack(spacing: 14) {
      if availablePlanDescriptors.isEmpty && !premiumManager.isLoading {
        Text(appLocalizedString(Localizable.premiumProductsUnavailable))
          .typography(.footnote)
          .themeText(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, Spacing.medium)
      } else {
        // Plan selector — equal-width, border-highlight, centered
        HStack(spacing: 10) {
          ForEach(orderedPlanDescriptors, id: \.id) { descriptor in
            planCard(descriptor)
              .frame(maxWidth: .infinity)
          }
        }
      }

      // Primary CTA
      primaryCTASection

      // Footer
      dockFooter
    }
    .padding(.horizontal, 20)
    .padding(.top, 24)
    .padding(.bottom, 0)
    .background {
      VStack(spacing: 0) {
        LinearGradient(
          colors: [
            Color.clear,
            Color.theme.backgroundPrimary.opacity(0.6),
            Color.theme.backgroundPrimary,
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: 36)

        Color.theme.backgroundPrimary
      }
      .ignoresSafeArea(edges: .bottom)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("paywall-purchase-dock")
  }

  private var primaryCTASection: some View {
    Group {
      if let product = selectedProduct {
        VStack(spacing: 4) {
          Button {
            HapticManager.shared.light()
            purchase(product)
          } label: {
            Text(contentState.primaryCTA)
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(Color.theme.buttonText)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 16)
              .background(
                RoundedRectangle(cornerRadius: 14)
                  .fill(Color.theme.buttonBackground)
              )
          }
          .buttonStyle(.plain)
          .disabled(isPurchasing)
          .opacity(isPurchasing ? 0.6 : 1)
          .accessibilityIdentifier("paywall-primary-cta")

          Text(billingDetailsText(for: product))
            .font(.system(size: 11))
            .themeText(.tertiary)
            .multilineTextAlignment(.center)

          Text(subscriptionDisclaimerText)
            .font(.system(size: 11))
            .themeText(.tertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("paywall-subscription-disclaimer")
        }
      } else if uiTestOverrides.usesStubPaywallPlans, contentState.selectedPlan != nil {
        Button {
          HapticManager.shared.light()
        } label: {
          Text(contentState.primaryCTA)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(Color.theme.buttonText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
              RoundedRectangle(cornerRadius: 14)
                .fill(Color.theme.buttonBackground)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywall-primary-cta")
      }
    }
  }

  private func planCard(_ descriptor: PaywallPlanDescriptor) -> some View {
    let isSelected = contentState.selectedPlan?.id == descriptor.id
    let isAnnual = descriptor.kind == .annual

    return Button {
      HapticManager.shared.light()
      selectedProductId = descriptor.id
      Analytics.productSelected(context: analyticsContext(selectedProductId: descriptor.id))
    } label: {
      VStack(spacing: 4) {
        // Name + compact savings badge
        HStack(spacing: 6) {
          Text(descriptor.displayName)
            .font(.system(size: 15, weight: .semibold))
            .themeText(.primary)

          if isAnnual, let savings = descriptor.savingsDescription {
            Text(savings)
              .font(.system(size: 10, weight: .bold))
              .foregroundColor(Color.theme.buttonText)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(
                Capsule()
                  .fill(Color.theme.buttonBackground)
              )
          }
        }

        // Price
        Text(descriptor.displayPrice + (isAnnual ? appLocalizedString(Localizable.premiumPerYear) : appLocalizedString(Localizable.premiumPerMonth)))
          .font(.system(size: 15))
          .themeText(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: 14)
          .fill(isSelected ? Color.theme.backgroundSecondary.opacity(0.5) : Color.clear)
          .overlay(
            RoundedRectangle(cornerRadius: 14)
              .stroke(
                isSelected ? Color.theme.textPrimary : Color.theme.cardBorder,
                lineWidth: isSelected ? 2 : 1
              )
          )
      )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("paywall-plan-\(descriptor.kind == .annual ? "annual" : "monthly")")
  }

  // MARK: - Footer

  private var dockFooter: some View {
    HStack(spacing: 16) {
      Link(
        appLocalizedString(Localizable.premiumTerms), destination: URL(string: "https://sotie.app/terms")!
      )
      .font(.system(size: 11))
      .themeText(.tertiary)
      .accessibilityIdentifier("paywall-terms")

      Button {
        HapticManager.shared.light()
        restorePurchases()
      } label: {
        Text(appLocalizedString(Localizable.premiumRestore))
          .font(.system(size: 11))
          .themeText(.tertiary)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("paywall-restore")

      Link(
        appLocalizedString(Localizable.premiumPrivacy),
        destination: URL(string: "https://sotie.app/privacy")!
      )
      .font(.system(size: 11))
      .themeText(.tertiary)
      .accessibilityIdentifier("paywall-privacy")
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 2)
    .padding(.bottom, 6)
  }



  // MARK: - Actions

  private func purchase(_ product: Product) {
    isPurchasing = true
    let context = analyticsContext(selectedProductId: product.id)

    Task {
      do {
        try await premiumManager.purchase(product, context: context)

        await MainActor.run {
          isPurchasing = false
          HapticManager.shared.success()
          closePaywall()
        }
      } catch {
        await MainActor.run {
          isPurchasing = false

          if let premiumError = error as? PremiumError,
            case .purchaseCancelled = premiumError
          {
            Analytics.purchaseCancelled(context: context)
            return
          }

          showError(error.localizedDescription)
        }
      }
    }
  }

  private func restorePurchases() {
    isPurchasing = true

    Task {
      do {
        try await premiumManager.restorePurchases()

        await MainActor.run {
          isPurchasing = false
          HapticManager.shared.success()
          closePaywall()
        }
      } catch {
        await MainActor.run {
          isPurchasing = false
          showError(error.localizedDescription)
        }
      }
    }
  }

  private func showError(_ message: String) {
    HapticManager.shared.error()
    errorMessage = message
    showError = true
  }

  private func resolveActiveSourceIfNeeded() {
    guard resolvedSource == nil else { return }

    if let attributedSource = NotificationManager.shared.paywallAttributionSource {
      resolvedSource = PaywallSource(rawValue: attributedSource)
      NotificationManager.shared.paywallAttributionSource = nil
      return
    }

    resolvedSource = source
  }

  private func selectPreferredProductIfNeeded() {
    let preferredId = preferredProductId(
      from: premiumManager.products,
      fallbackDescriptors: availablePlanDescriptors
    )
    guard !preferredId.isEmpty else { return }

    if selectedProductId.isEmpty || !availablePlanDescriptors.contains(where: { $0.id == selectedProductId }) {
      selectedProductId = preferredId
    }
  }

  private func preferredProductId(
    from products: [Product],
    fallbackDescriptors: [PaywallPlanDescriptor] = []
  ) -> String {
    if let annual = products.first(where: { $0.id.contains("annual") }) {
      return annual.id
    }

    if let annual = fallbackDescriptors.first(where: { $0.kind == .annual }) {
      return annual.id
    }

    return products.first?.id ?? fallbackDescriptors.first?.id ?? ""
  }

  private func analyticsContext(selectedProductId: String? = nil) -> PaywallAnalyticsContext {
    PaywallAnalyticsContext(
      source: activeSource,
      variantId: variantId,
      eligibleForTrial: resolvedTrialEligibility,
      selectedProductId: selectedProductId ?? contentState.selectedPlan?.id ?? "none"
    )
  }

  private var subscriptionDisclaimerText: String {
    appLocalizedString(Localizable.premiumSubscriptionDisclaimer)
  }

  private func planDescriptor(for product: Product) -> PaywallPlanDescriptor? {
    let kind: PaywallPlanKind = product.id.contains("annual") ? .annual : .monthly
    let savingsInfo = kind == .annual ? calculateAnnualSavingsInfo() : nil
    let fullBillingDescription = kind == .annual
      ? "\(product.displayPrice) \(appLocalizedString(Localizable.premiumBilledAnnually))"
      : "\(product.displayPrice) \(appLocalizedString(Localizable.premiumBilledMonthly))"

    return PaywallPlanDescriptor(
      id: product.id,
      kind: kind,
      displayName: kind == .annual ? appLocalizedString(Localizable.premiumAnnual) : appLocalizedString(Localizable.premiumMonthly),
      displayPrice: product.displayPrice,
      fullBillingDescription: fullBillingDescription,
      monthlyEquivalentDescription: savingsInfo?.monthlyEquivalentText,
      savingsDescription: savingsInfo?.percentText,
      hasIntroOffer: product.subscription?.introductoryOffer != nil
    )
  }

  private struct AnnualSavingsInfo {
    let percentText: String
    let monthlyEquivalentText: String
  }

  private func calculateAnnualSavingsInfo() -> AnnualSavingsInfo? {
    guard
      let monthlyProduct = premiumManager.products.first(where: { $0.id.contains("monthly") }),
      let annualProduct = premiumManager.products.first(where: { $0.id.contains("annual") })
    else {
      return nil
    }

    let monthlyYearlyCost = monthlyProduct.price * 12
    let annualCost = annualProduct.price

    guard monthlyYearlyCost > 0 else { return nil }

    let savings = monthlyYearlyCost - annualCost
    let savingsPercent = NSDecimalNumber(decimal: savings)
      .dividing(by: NSDecimalNumber(decimal: monthlyYearlyCost))
      .multiplying(by: 100)
      .rounding(accordingToBehavior: nil)
      .intValue

    let monthlyEquivalent = NSDecimalNumber(decimal: annualCost).dividing(by: 12)
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = annualProduct.priceFormatStyle.locale
    formatter.currencyCode = annualProduct.priceFormatStyle.currencyCode
    formatter.maximumFractionDigits = 2

    let monthlyString = formatter.string(from: monthlyEquivalent) ?? ""

    return AnnualSavingsInfo(
      percentText: appLocalizedString(Localizable.premiumSavePercent, arguments: savingsPercent),
      monthlyEquivalentText: appLocalizedString(Localizable.premiumMonthlyEquivalent, arguments: monthlyString)
    )
  }

  private func billingDetailsText(for product: Product) -> String {
    let isAnnual = product.id.contains("annual")

    if resolvedTrialEligibility,
      let offer = product.subscription?.introductoryOffer
    {
      let days = trialDays(from: offer)
      let periodWord = isAnnual
        ? appLocalizedString(Localizable.premiumBillingPerYear)
        : appLocalizedString(Localizable.premiumBillingPerMonth)

      return appLocalizedString(
        Localizable.premiumTrialInfoDynamic,
        arguments: days, product.displayPrice, " \(periodWord)"
      )
    }

    let periodWord = isAnnual
      ? appLocalizedString(Localizable.premiumBillingPerYear)
      : appLocalizedString(Localizable.premiumBillingPerMonth)
    return "\(product.displayPrice) \(periodWord)"
  }

  private func trialDays(from offer: Product.SubscriptionOffer) -> Int {
    let period = offer.period
    switch period.unit {
    case .day:   return period.value
    case .week:  return period.value * 7
    case .month: return period.value * 30
    case .year:  return period.value * 365
    @unknown default: return period.value
    }
  }
}

#Preview {
  PaywallView(source: .settings)
    .environment(\.theme, Theme())
}

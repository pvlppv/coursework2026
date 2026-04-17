//
//  OnboardingPaywallView.swift
//  Sotie
//
//  Screen 34 (final onboarding step): hard paywall.
//  Reference-style layout — 3-day trial timeline, monthly/yearly toggle,
//  big CTA, full legal footer. Reuses PremiumManager for purchase + restore.
//
//  Hard paywall: no close button. Only ways out are a successful purchase
//  or a successful restore, both of which call `onClose`.
//

import SwiftUI
import StoreKit

struct OnboardingPaywallView: View {
    let onBack: () -> Void
    let onClose: () -> Void

    @StateObject private var premiumManager = PremiumManager.shared
    @State private var selectedProductId: String = ""
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var isRefreshing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var contentVisible = false

    // MARK: - Plan helpers

    private var annualProduct: Product? {
        premiumManager.products.first(where: { $0.id == PremiumProduct.annual.rawValue })
    }

    private var monthlyProduct: Product? {
        premiumManager.products.first(where: { $0.id == PremiumProduct.monthly.rawValue })
    }

    private var selectedProduct: Product? {
        premiumManager.products.first(where: { $0.id == selectedProductId })
    }

    private var hasIntroOffer: Bool {
        // Eligibility for the actual intro offer redemption (async-checked).
        // Drives the disclosure copy ("3 days free, then ...") and CTA text.
        guard let annualProduct else { return false }
        return annualProduct.subscription?.introductoryOffer != nil
            && premiumManager.isEligibleForIntroOffer
    }

    /// Whether to show the trial timeline. Only when the annual plan is
    /// selected AND that plan has an intro offer configured. Otherwise we
    /// show the benefits list (closer to a "value pitch" paywall).
    private var showsTimeline: Bool {
        selectedProductId == PremiumProduct.annual.rawValue && showsTrialBadge
    }

    /// Whether to show the "3 DAYS FREE" badge — based on the product
    /// configuration alone (synchronous), not user eligibility. The badge is
    /// a marketing affordance; Apple decides at purchase time whether the
    /// trial actually applies, so for already-redeemed-elsewhere edge cases
    /// the user just sees a regular charge.
    private var showsTrialBadge: Bool {
        annualProduct?.subscription?.introductoryOffer != nil
    }

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar — back button on left, refresh button on right.
                // The refresh button reloads products + re-checks intro
                // eligibility, useful when StoreKit fails to populate the
                // products array (rare network case, but the hard paywall
                // gives users no other recovery path).
                HStack {
                    Button {
                        HapticManager.shared.soft()
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .themeText(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        refreshProducts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .themeText(.primary)
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .accessibilityLabel("Refresh products")
                    .accessibilityIdentifier("onboarding-paywall-refresh")
                }
                .padding(.horizontal, Spacing.small)

                // Content area — uses Spacer to distribute vertical space
                // so the title + middle section + plan toggle don't all
                // collapse to the top of the screen with the bottom dock
                // pinned at the bottom edge.
                VStack(spacing: Spacing.large) {
                    // Title
                    title

                    // Middle section — timeline when annual+trial selected,
                    // benefits otherwise (monthly or annual without trial).
                    Group {
                        if showsTimeline {
                            timeline
                        } else {
                            benefitsList
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: Spacing.medium)

                    // Plan toggle
                    planToggle
                }
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.medium)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 12)

                // Bottom dock — pinned at bottom
                bottomDock
                    .padding(.horizontal, Spacing.large)
                    .padding(.bottom, Spacing.medium)
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 16)
            }
        }
        .alert(appLocalizedString(Localizable.premiumErrorPurchaseFailed), isPresented: $showError) {
            Button(appLocalizedString(Localizable.cancel), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            HapticManager.shared.gentle()
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                contentVisible = true
            }
            Task {
                await premiumManager.checkIntroOfferEligibility()
                await MainActor.run {
                    selectPreferredProductIfNeeded()
                }
            }

            Analytics.paywallViewed(context: analyticsContext())
        }
        .onChange(of: premiumManager.products) { _, _ in
            selectPreferredProductIfNeeded()
        }
        .onChange(of: premiumManager.subscriptionStatus) { _, status in
            // Auto-close when premium becomes active (covers transaction-listener races).
            if status.isPremium {
                onClose()
            }
        }
    }

    // MARK: - Title

    private var title: some View {
        Text(showsTimeline
             ? appLocalizedString(Localizable.onboardingFlowPaywallTitle)
             : appLocalizedString(Localizable.onboardingFlowPaywallTitleBenefits))
            .font(.system(size: 26, weight: .bold))
            .themeText(.primary)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.small)
    }

    // MARK: - Benefits list (shown when a non-trial plan is selected)

    /// Three checkmark rows pitching the value of the subscription. Used as
    /// a fallback when the trial timeline doesn't apply (e.g. monthly is
    /// selected, or the user is no longer eligible for the intro offer).
    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            benefitRow(
                title: appLocalizedString(Localizable.onboardingFlowPaywallBenefit1Title),
                body: appLocalizedString(Localizable.onboardingFlowPaywallBenefit1Body)
            )
            benefitRow(
                title: appLocalizedString(Localizable.onboardingFlowPaywallBenefit2Title),
                body: appLocalizedString(Localizable.onboardingFlowPaywallBenefit2Body)
            )
            benefitRow(
                title: appLocalizedString(Localizable.onboardingFlowPaywallBenefit3Title),
                body: appLocalizedString(Localizable.onboardingFlowPaywallBenefit3Body)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefitRow(title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .themeText(.primary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .themeText(.primary)

                Text(body)
                    .font(.system(size: 16, weight: .regular))
                    .themeText(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Timeline

    /// Three-row connected timeline. Each row is independently laid out —
    /// the icon sits at the top of the row (aligned with the title), and a
    /// thick vertical connector line fills the remaining vertical space
    /// down to the next icon. The last row has no line below it.
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineRow(
                index: 0,
                icon: "lock.open.fill",
                title: appLocalizedString(Localizable.onboardingFlowPaywallTimelineTodayTitle),
                body: appLocalizedString(Localizable.onboardingFlowPaywallTimelineTodayBody)
            )
            timelineRow(
                index: 1,
                icon: "bell.fill",
                title: appLocalizedString(Localizable.onboardingFlowPaywallTimelineDay2Title),
                body: appLocalizedString(Localizable.onboardingFlowPaywallTimelineDay2Body)
            )
            timelineRow(
                index: 2,
                icon: "creditcard.fill",
                title: appLocalizedString(Localizable.onboardingFlowPaywallTimelineDay3Title),
                body: trialEndCopy
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timelineRow(index: Int, icon: String, title: String, body: String) -> some View {
        let iconSize: CGFloat = 36
        let lineWidth: CGFloat = 6
        let isLast = index == 2

        return HStack(alignment: .top, spacing: 14) {
            // Left rail — icon at top, connector line filling the rest of
            // the row below it. Last row has no line.
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.theme.backgroundTertiary)
                        .frame(width: iconSize, height: iconSize)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .themeText(.primary)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color.theme.divider)
                        .frame(width: lineWidth)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: iconSize)

            // Right column — text. Bottom padding gives breathing room
            // before the next row's icon (when not last).
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .themeText(.primary)

                Text(body)
                    .font(.system(size: 16, weight: .regular))
                    .themeText(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : Spacing.medium)
        }
    }

    /// "You'll be charged on [date+3 days] unless you cancel anytime before."
    private var trialEndCopy: String {
        let calendar = Calendar.current
        let chargeDate = calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        let formatter = Foundation.DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd, yyyy")
        let dateString = formatter.string(from: chargeDate)
        return appLocalizedString(
            Localizable.onboardingFlowPaywallTimelineDay3Body,
            arguments: dateString
        )
    }

    // MARK: - Plan Toggle

    private var planToggle: some View {
        HStack(spacing: 12) {
            if let monthly = monthlyProduct {
                planCard(
                    product: monthly,
                    title: appLocalizedString(Localizable.premiumMonthly),
                    priceLine: monthlyPriceLine(monthly),
                    isSelected: selectedProductId == monthly.id,
                    badge: nil
                )
            }

            if let annual = annualProduct {
                planCard(
                    product: annual,
                    title: appLocalizedString(Localizable.onboardingFlowPaywallPlanYearly),
                    priceLine: annualPriceLine(annual),
                    isSelected: selectedProductId == annual.id,
                    badge: showsTrialBadge
                        ? appLocalizedString(Localizable.onboardingFlowPaywallBadgeTrial)
                        : nil
                )
            }
        }
    }

    private func planCard(
        product: Product,
        title: String,
        priceLine: String,
        isSelected: Bool,
        badge: String?
    ) -> some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(.easeOut(duration: 0.2)) {
                selectedProductId = product.id
            }
            Analytics.productSelected(context: analyticsContext(selectedProductId: product.id))
        } label: {
            VStack(spacing: 0) {
                // Badge slot — always reserves vertical space so cards stay aligned.
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.theme.buttonText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.theme.buttonBackground)
                        )
                        .padding(.bottom, -10)  // overlap into the card
                        .zIndex(1)
                } else {
                    // Empty equivalent so both cards line up
                    Color.clear
                        .frame(height: 22 - 10)
                }

                // Card body
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .themeText(.secondary)

                        Text(priceLine)
                            .font(.system(size: 18, weight: .bold))
                            .themeText(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .padding(.horizontal, Spacing.medium)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                            .fill(isSelected
                                  ? Color.theme.backgroundTertiary
                                  : Color.theme.backgroundSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                            .stroke(isSelected
                                    ? Color.theme.textPrimary
                                    : Color.theme.divider,
                                    lineWidth: isSelected ? 2 : 1)
                    )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .themeText(.primary)
                            .padding(8)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func monthlyPriceLine(_ product: Product) -> String {
        // "$9.99/mo"
        appLocalizedString(
            Localizable.onboardingFlowPaywallPriceMonthly,
            arguments: product.displayPrice
        )
    }

    private func annualPriceLine(_ product: Product) -> String {
        // "$68.99"
        product.displayPrice
    }

    // MARK: - Bottom Dock

    private var bottomDock: some View {
        VStack(spacing: 12) {
            // Reassurance line — switches between "No Payment Due Now" (when
            // a free trial actually applies) and "No Commitment · Cancel
            // Anytime" (monthly or post-trial annual).
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .themeText(.secondary)

                Text(showsTimeline
                     ? appLocalizedString(Localizable.onboardingFlowPaywallNoPayment)
                     : appLocalizedString(Localizable.onboardingFlowPaywallNoCommitment))
                    .font(.system(size: 14, weight: .medium))
                    .themeText(.secondary)
            }

            // Primary CTA
            OnboardingPrimaryButton(
                isEnabled: selectedProduct != nil,
                isLoading: isPurchasing,
                action: {
                    guard let product = selectedProduct else { return }
                    purchase(product)
                }
            ) {
                Text(primaryCTAText)
            }

            // Disclosure + footer share a tight 6pt rhythm.
            VStack(spacing: 6) {
                Text(disclosureText)
                    .font(.system(size: 11, weight: .regular))
                    .themeText(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, Spacing.small)

                PaywallLegalFooter(onRestore: { restorePurchases() }, layout: .compact)
            }
        }
    }

    private var primaryCTAText: String {
        // Use trial-CTA whenever annual is selected and the product has an
        // intro offer configured. Eligibility is enforced by Apple at purchase.
        // Otherwise (monthly, or annual without intro), use a forward-leaning
        // "Start My Journey" CTA matching the value-pitch paywall variant.
        if showsTrialBadge && selectedProductId == PremiumProduct.annual.rawValue {
            return appLocalizedString(Localizable.onboardingFlowPaywallCTAStartTrial)
        }
        return appLocalizedString(Localizable.onboardingFlowPaywallCTAStartJourney)
    }

    /// "3 days free, then $68.99 per year. Plan auto-renews unless you cancel. Cancel in the App Store."
    private var disclosureText: String {
        let priceString: String = {
            if selectedProductId == PremiumProduct.annual.rawValue,
               let annual = annualProduct {
                return appLocalizedString(
                    Localizable.onboardingFlowPaywallDisclosurePerYear,
                    arguments: annual.displayPrice
                )
            }
            if let monthly = monthlyProduct {
                return appLocalizedString(
                    Localizable.onboardingFlowPaywallDisclosurePerMonth,
                    arguments: monthly.displayPrice
                )
            }
            return ""
        }()

        if showsTrialBadge && selectedProductId == PremiumProduct.annual.rawValue {
            return appLocalizedString(
                Localizable.onboardingFlowPaywallDisclosureWithTrial,
                arguments: priceString
            )
        }
        return appLocalizedString(
            Localizable.onboardingFlowPaywallDisclosureNoTrial,
            arguments: priceString
        )
    }

    // MARK: - Selection

    private func selectPreferredProductIfNeeded() {
        if !premiumManager.products.contains(where: { $0.id == selectedProductId }) {
            // Default: annual (best value, plus has the trial)
            if let annual = annualProduct {
                selectedProductId = annual.id
            } else if let first = premiumManager.products.first {
                selectedProductId = first.id
            }
        }
    }

    // MARK: - Purchase / Restore

    private func purchase(_ product: Product) {
        guard !isPurchasing else { return }
        isPurchasing = true
        let context = analyticsContext(selectedProductId: product.id)

        Task {
            do {
                try await premiumManager.purchase(product, context: context)
                await MainActor.run {
                    isPurchasing = false
                    HapticManager.shared.success()
                    OnboardingDiscountActivityManager.shared.end(reason: .purchased)
                    onClose()
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    if let premiumError = error as? PremiumError,
                       case .purchaseCancelled = premiumError {
                        Analytics.purchaseCancelled(context: context)
                        // Squeeze: user dismissed Apple's StoreKit sheet
                        // without buying. If the onboarding-discount timer
                        // is still alive, surface the discount paywall as
                        // a final retention attempt. The manager no-ops
                        // when the timer has already expired.
                        OnboardingDiscountActivityManager.shared.requestPresentation()
                        return
                    }
                    showError(error.localizedDescription)
                }
            }
        }
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true

        Task {
            do {
                try await premiumManager.restorePurchases()
                await MainActor.run {
                    isRestoring = false
                    if premiumManager.subscriptionStatus.isPremium {
                        HapticManager.shared.success()
                        onClose()
                    }
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
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

    /// Reloads products + intro-offer eligibility. Spins the icon once
    /// regardless of how fast the network call completes.
    private func refreshProducts() {
        guard !isRefreshing else { return }
        HapticManager.shared.light()
        withAnimation(.easeInOut(duration: 0.6)) {
            isRefreshing = true
        }

        Task {
            await premiumManager.loadProducts()
            await premiumManager.checkIntroOfferEligibility()
            await MainActor.run {
                selectPreferredProductIfNeeded()
                // Reset rotation cleanly so the next tap animates again.
                isRefreshing = false
            }
        }
    }

    // MARK: - Analytics

    private func analyticsContext(selectedProductId: String? = nil) -> PaywallAnalyticsContext {
        PaywallAnalyticsContext(
            source: .onboardingCheckpoint,
            variantId: PaywallVariant.reviewSafeBaseline.rawValue,
            eligibleForTrial: hasIntroOffer,
            selectedProductId: selectedProductId ?? self.selectedProductId
        )
    }
}

#Preview {
    OnboardingPaywallView(onBack: {}, onClose: {})
        .environment(\.theme, Theme())
}

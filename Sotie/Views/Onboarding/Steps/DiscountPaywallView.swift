//
//  DiscountPaywallView.swift
//  Sotie
//
//  Limited-time discount "squeeze" paywall.
//  Presented as a sheet on top of the onboarding flow when:
//    - The user taps the onboarding-discount Live Activity.
//    - The user dismisses Apple's StoreKit purchase sheet (i.e. pulls down
//      on the system buy sheet from `OnboardingPaywallView`).
//
//  Layout intentionally mirrors the "One Time Offer" reference Pavel shared:
//
//      ╳
//      One Time Offer
//      50% OFF
//      ⚠️ You will not see this offer again
//      ┌──────────────────────────────────┐
//      │       Only $0.66/week            │
//      │   *Lowest price ever. Billed yr  │
//      └─────────── ⏰ 23:59:38 ───────────┘
//                  (Present image)
//      Claim your one time offer
//      Privacy   Terms
//
//  Mapped to Sotie's monochrome palette: any orange in the reference
//  becomes `Color.theme.buttonBackground` (black in light, white in
//  dark), text on those surfaces uses `Color.theme.buttonText`. The
//  alarm pill, CTA, and gift illustration share the same primary
//  treatment so the eye reads them as one chain of urgency.
//
//  One visual timer — the paywall's own 3-min countdown — runs purely
//  for show. No "expired" handling, no disabled CTA: when it hits
//  zero it just sits at "0:00". The Live Activity on the lock screen
//  is independent and runs its own 24h ad.

import Combine
import StoreKit
import SwiftUI

struct DiscountPaywallView: View {
    let onClose: () -> Void

    @StateObject private var premiumManager = PremiumManager.shared
    @StateObject private var activityManager = OnboardingDiscountActivityManager.shared

    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var contentVisible = false

    /// Paywall-local visual countdown. Reset to 3 minutes from now
    /// every time the sheet appears. Pure decoration — no behaviour
    /// flips when it reaches zero.
    @State private var paywallExpiresAt: Date = Date().addingTimeInterval(3 * 60)

    private var annualProduct: Product? {
        // Prefer the real discounted SKU. Apple charges this product's
        // actual price (50% of the regular annual), so what the user
        // sees in the paywall is what gets billed. Falls back to the
        // regular annual only if the discount product hasn't loaded
        // yet (cold start, etc.) — caller stays robust.
        premiumManager.products.first(where: { $0.id == PremiumProduct.annualDiscount.rawValue })
            ?? premiumManager.products.first(where: { $0.id == PremiumProduct.annual.rawValue })
    }

    /// Regular (non-discounted) annual product, used for the strike-
    /// through "was $X" comparison line. Optional — if it failed to
    /// load we just hide the comparison.
    private var regularAnnualProduct: Product? {
        premiumManager.products.first(where: { $0.id == PremiumProduct.annual.rawValue })
    }

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: Spacing.large) {
                        headlineBlock
                        priceCard
                        giftIllustration
                    }
                    .padding(.horizontal, Spacing.large)
                    .padding(.top, Spacing.xSmall)
                    .padding(.bottom, Spacing.medium)
                }
                .scrollIndicators(.hidden)

                bottomDock
                    .padding(.horizontal, Spacing.large)
                    .padding(.bottom, Spacing.medium)
            }
            .opacity(contentVisible ? 1 : 0)
            .offset(y: contentVisible ? 0 : 12)
        }
        .alert(
            appLocalizedString(Localizable.premiumErrorPurchaseFailed),
            isPresented: $showError
        ) {
            Button(appLocalizedString(Localizable.cancel), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            HapticManager.shared.gentle()
            // Reset the visual countdown every time the sheet opens.
            paywallExpiresAt = Date().addingTimeInterval(3 * 60)
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                contentVisible = true
            }
            Task {
                if premiumManager.products.isEmpty {
                    await premiumManager.loadProducts()
                }
                await premiumManager.checkIntroOfferEligibility()
            }
        }
        .onChange(of: premiumManager.subscriptionStatus) { _, status in
            if status.isPremium {
                onClose()
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                HapticManager.shared.soft()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .themeText(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appLocalizedString(Localizable.cancel))

            Spacer()
        }
        .padding(.horizontal, Spacing.small)
    }

    // MARK: - Headline Block

    private var headlineBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appLocalizedString(Localizable.onboardingDiscountPaywallTitle))
                .font(.system(size: 30, weight: .heavy))
                .themeText(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(appLocalizedString(
                Localizable.onboardingDiscountPaywallPercentOff,
                arguments: activityManager.discountPercent
            ))
                .font(.system(size: 38, weight: .heavy))
                .themeText(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .themeText(.primary)
                Text(appLocalizedString(Localizable.onboardingDiscountPaywallWarning))
                    .font(.system(size: 14, weight: .medium))
                    .themeText(.primary)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Price Card

    private var priceCard: some View {
        VStack(spacing: 6) {
            priceHeroLine

            if let regular = regularAnnualProduct,
               let discounted = annualProduct,
               regular.id != discounted.id {
                // Strike-through "was $X.XX/year" line — visible proof
                // of the discount, not just a "% off" headline. Only
                // shown when both products loaded and they're distinct
                // (so we never strike through the same price as itself).
                HStack(spacing: 6) {
                    Text(annualPerYearLine(discounted))
                        .font(.system(size: 12, weight: .semibold))
                        .themeText(.primary)

                    Text(annualPerYearLine(regular))
                        .font(.system(size: 12, weight: .regular))
                        .themeText(.tertiary)
                        .strikethrough(true, color: Color.theme.textTertiary)
                }
            }

            Text(appLocalizedString(Localizable.onboardingDiscountPaywallPriceLowest))
                .font(.system(size: 12, weight: .regular))
                .themeText(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, Spacing.large)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cornerRadiusLarge)
                .fill(Color.theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cornerRadiusLarge)
                .stroke(Color.theme.textPrimary, lineWidth: 2)
        )
        .overlay(alignment: .bottom) {
            alarmPill
                .offset(y: 18)
        }
        .padding(.bottom, 18) // room for the overhanging pill
    }

    /// "$34.50/year" formatted line for a given yearly product.
    /// User-facing copy uses "year" rather than internal "/yr" / "annual"
    /// terminology — the rest of the app's onboarding paywall already
    /// uses "Yearly" via `Localizable.onboardingFlowPaywallPlanYearly`,
    /// so the two surfaces stay consistent.
    private func annualPerYearLine(_ product: Product) -> String {
        appLocalizedString(
            Localizable.onboardingDiscountPaywallPricePerYear,
            arguments: product.displayPrice
        )
    }

    /// "Only $0.66/week" — the hero pricing line.
    private var priceHeroLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(appLocalizedString(Localizable.onboardingDiscountPaywallPriceOnly))
                .font(.system(size: 22, weight: .semibold))
                .themeText(.primary)

            Text(weeklyPriceString)
                .font(.system(size: 26, weight: .heavy))
                .themeText(.primary)
                .monospacedDigit()

            Text(appLocalizedString(Localizable.onboardingDiscountPaywallPricePerWeek))
                .font(.system(size: 22, weight: .semibold))
                .themeText(.primary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// Weekly equivalent of the actual discounted annual price,
    /// formatted in the product's currency. Reads from the real
    /// `annual.discount` SKU so the displayed price is what gets
    /// charged.
    private var weeklyPriceString: String {
        guard let annual = annualProduct else { return "—" }

        let weekly = NSDecimalNumber(decimal: annual.price)
            .dividing(by: NSDecimalNumber(value: 52))

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = annual.priceFormatStyle.locale
        formatter.currencyCode = annual.priceFormatStyle.currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        return formatter.string(from: weekly) ?? annual.displayPrice
    }

    /// Alarm pill that overhangs the price card's bottom edge — same
    /// composition as the reference. The 3-px stroke matches the card
    /// fill so it reads as if the pill is "punched through" the card
    /// border, instead of the previous border-on-pill that looked like
    /// a sticker.
    @ViewBuilder
    private var alarmPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 13, weight: .heavy))
            countdownText
                .monospacedDigit()
                .font(.system(size: 15, weight: .heavy))
        }
        .foregroundColor(Color.theme.buttonText)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.theme.buttonBackground)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.theme.cardBackground, lineWidth: 3)
        )
        .accessibilityIdentifier("discount-paywall-countdown")
    }

    /// Live-ticking countdown built straight into SwiftUI — no
    /// per-second `Timer`, no expired branch. When `paywallExpiresAt`
    /// passes, `Text(timerInterval:)` naturally settles at "0:00".
    private var countdownText: some View {
        Text(timerInterval: Date()...paywallExpiresAt,
             countsDown: true,
             showsHours: false)
    }

    // MARK: - Gift Illustration

    /// Big, centred gift render. The lock-screen Live Activity uses a
    /// downsized `Present` asset (Live Activity widget extensions
    /// have a tight memory budget), so on the paywall — which has no
    /// such limit — we use a higher-resolution `PresentLarge` so the
    /// 220×220 render stays crisp.
    private var giftIllustration: some View {
        Image("PresentLarge")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 220, height: 220)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Dock (CTA + footer)

    private var bottomDock: some View {
        VStack(spacing: 12) {
            ctaButton
            Text(disclosureText)
                .font(.system(size: 11, weight: .regular))
                .themeText(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            PaywallLegalFooter(onRestore: { restorePurchases() }, layout: .compact)
        }
    }

    /// Big primary CTA — solid pill with bold label, no decorative
    /// pointing emojis (they read awkward in our monochrome system).
    /// The button alone carries the action. No expired state — the
    /// CTA is always live as long as the product loaded.
    private var ctaButton: some View {
        Button {
            guard let product = annualProduct else { return }
            purchase(product)
        } label: {
            HStack(spacing: 10) {
                if isPurchasing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.theme.buttonText)
                }
                Text(appLocalizedString(Localizable.onboardingDiscountPaywallCta))
                    .font(.system(size: 17, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundColor(Color.theme.buttonText)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.theme.buttonBackground)
            )
            .opacity(annualProduct == nil ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(annualProduct == nil || isPurchasing)
        .accessibilityIdentifier("discount-paywall-cta")
    }

    /// Disclosure shows the *real* annual price Apple will charge, with
    /// the auto-renew language StoreKit reviewers expect. We do NOT
    /// imply a discount here — that's the job of the headline + price
    /// card framing. Source of truth for the actual amount billed.
    private var disclosureText: String {
        guard let product = annualProduct else { return "" }
        return appLocalizedString(
            Localizable.onboardingFlowPaywallDisclosureNoTrial,
            arguments: product.displayPrice
        )
    }

    // MARK: - Purchase / Restore

    private func purchase(_ product: Product) {
        guard !isPurchasing else { return }
        isPurchasing = true
        let context = PaywallAnalyticsContext(
            source: .custom("onboarding_discount"),
            variantId: PaywallVariant.reviewSafeBaseline.rawValue,
            eligibleForTrial: false,
            selectedProductId: product.id
        )

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
                        OnboardingDiscountActivityManager.shared.end(reason: .purchased)
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
}

#Preview {
    DiscountPaywallView(onClose: {})
        .environment(\.theme, Theme())
}

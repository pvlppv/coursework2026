//
//  TryNowDemoView.swift
//  Sotie
//
//  Screen 32: "we want you to try sotie for free"
//  Shows a phone-shaped looping demo of the app, "Try Now" CTA,
//  and "no payment due now" reassurance. Sets up the user mentally
//  for the trial-reminder + paywall steps that follow.
//

import SwiftUI

struct TryNowDemoView: View {
    let onBack: () -> Void
    let onContinue: () -> Void
    let onRestore: () -> Void

    @StateObject private var premiumManager = PremiumManager.shared
    @State private var titleVisible = false
    @State private var mockupVisible = false
    @State private var ctaVisible = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with back button
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
                }
                .padding(.horizontal, Spacing.small)

                Spacer().frame(height: Spacing.medium)

                // Title
                Text(appLocalizedString(Localizable.onboardingFlowTryNowTitle))
                    .font(.system(size: 26, weight: .bold))
                    .themeText(.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.large)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 8)

                Spacer().frame(height: Spacing.large)

                // Phone-shaped demo loop
                phoneMockup
                    .opacity(mockupVisible ? 1 : 0)
                    .scaleEffect(mockupVisible ? 1 : 0.94)

                Spacer()

                // "No payment due now" + CTA + footer
                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .themeText(.secondary)

                        Text(appLocalizedString(Localizable.onboardingFlowTryNowNoPayment))
                            .font(.system(size: 14, weight: .medium))
                            .themeText(.secondary)
                    }

                    OnboardingPrimaryButton(
                        appLocalizedString(Localizable.onboardingFlowTryNowCTA, arguments: zeroPriceString),
                        action: { onContinue() }
                    )
                    PaywallLegalFooter(
                        onRestore: { onRestore() },
                        pricingTease: pricingTeaseText,
                        layout: .brief
                    )
                }
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.large)
                .opacity(ctaVisible ? 1 : 0)
                .offset(y: ctaVisible ? 0 : 12)
            }
        }
        .onAppear {
            HapticManager.shared.gentle()
            startAnimations()
        }
    }

    // MARK: - Phone-shaped looping video container

    private var phoneMockup: some View {
        let cornerRadius: CGFloat = 38
        return LoopingVideoPlayer(videoName: "onboarding_demo_loop")
            .aspectRatio(9.0 / 19.5, contentMode: .fit)
            .frame(maxWidth: 260)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.theme.textPrimary.opacity(0.85), lineWidth: 6)
            )
            .themeShadow(.large)
    }

    /// Triggers a real App Store restore. If a valid receipt is found and
    /// the user is now premium, skip ahead to the home screen by completing
    /// onboarding. Errors are swallowed silently — user just stays on screen.
    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
            titleVisible = true
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.6)) {
            mockupVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(1.2)) {
            ctaVisible = true
        }
    }

    /// "Just $68.99 per year ($5.75/mo)" — falls back to a plain version if
    /// products haven't loaded yet (cold launch). Reads the annual product
    /// price from PremiumManager and computes a monthly equivalent.
    private var pricingTeaseText: String {
        OnboardingPricingFormatter.teaseLine(for: premiumManager.products)
    }

    /// "$0.00" / "0,00 ₽" / "¥0" — locale-aware zero in the App Store
    /// account's currency. Slotted into the "Try for %@" CTA so users in
    /// every region see their own currency. Falls back to a plain "$0.00"
    /// if products haven't loaded yet so the CTA never reads "Try for ".
    private var zeroPriceString: String {
        OnboardingPricingFormatter.zeroPriceString(for: premiumManager.products)
    }
}

#Preview {
    TryNowDemoView(onBack: {}, onContinue: {}, onRestore: {})
        .environment(\.theme, Theme())
}

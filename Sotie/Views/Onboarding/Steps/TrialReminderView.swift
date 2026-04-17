//
//  TrialReminderView.swift
//  Sotie
//
//  Screen 33: "we'll send you a reminder before your free trial ends"
//  Reassurance step before the actual paywall. Shows a bell icon with a
//  red "1" badge mimicking a notification preview.
//
//  Apple's auto-renewable subscription guidelines effectively require this
//  disclosure, so it doubles as a UX moment AND a compliance moment.
//

import SwiftUI

struct TrialReminderView: View {
    let onBack: () -> Void
    let onContinue: () -> Void
    let onRestore: () -> Void

    @StateObject private var premiumManager = PremiumManager.shared

    @State private var titleVisible = false
    @State private var bellVisible = false
    @State private var badgeVisible = false
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

                Spacer()

                // Title
                Text(appLocalizedString(Localizable.onboardingFlowTrialReminderTitle))
                    .font(.system(size: 26, weight: .bold))
                    .themeText(.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.large)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 8)

                Spacer().frame(height: 60)

                // Bell with red badge "1"
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 110, weight: .regular))
                        .themeText(.tertiary)
                        .opacity(bellVisible ? 1 : 0)
                        .scaleEffect(bellVisible ? 1 : 0.85)

                    // Red badge — only loud color in our B&W system, used
                    // sparingly for the notification metaphor.
                    Text("1")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.red)
                        )
                        .offset(x: 12, y: -8)
                        .opacity(badgeVisible ? 1 : 0)
                        .scaleEffect(badgeVisible ? 1 : 0)
                }

                Spacer()

                // "No payment due now" + CTA
                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .themeText(.secondary)

                        Text(appLocalizedString(Localizable.onboardingFlowTrialReminderNoPayment))
                            .font(.system(size: 14, weight: .medium))
                            .themeText(.secondary)
                    }

                    OnboardingPrimaryButton(
                        appLocalizedString(Localizable.onboardingFlowTrialReminderCTA),
                        action: { onContinue() }
                    )

                    // Disclosure + footer share a tight 6pt rhythm so the
                    // fine-print block reads as one visual unit instead of
                    // two disconnected groups.
                    VStack(spacing: 6) {
                        Text(appLocalizedString(Localizable.onboardingFlowTrialReminderDisclosure))
                            .font(.system(size: 11, weight: .regular))
                            .themeText(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.medium)

                        PaywallLegalFooter(
                            onRestore: { onRestore() },
                            pricingTease: OnboardingPricingFormatter.teaseLine(for: premiumManager.products),
                            layout: .brief
                        )
                    }
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

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
            titleVisible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.7)) {
            bellVisible = true
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(1.2)) {
            badgeVisible = true
        }
        // Tiny "ping" right as the red "1" badge pops in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            HapticManager.shared.selection()
        }
        withAnimation(.easeOut(duration: 0.6).delay(1.6)) {
            ctaVisible = true
        }
    }
}

#Preview {
    TrialReminderView(onBack: {}, onContinue: {}, onRestore: {})
        .environment(\.theme, Theme())
}

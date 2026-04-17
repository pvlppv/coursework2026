//
//  JourneySummaryView.swift
//  Sotie
//
//  Screen 21: "thanks, [name]."
//  Summary screen showing user's selections in labeled cards.
//  Labels are in rounded pill badges above the emoji+value.
//  Body text is primary color, bigger, more prominent.
//

import SwiftUI

struct JourneySummaryView: View {
    let name: String
    let vision: OnboardingVision?
    let feeling: ThoughtFeeling?
    let blocker: ThoughtBlocker?
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isVisible = false
    @State private var card1Visible = false
    @State private var card2Visible = false
    @State private var card3Visible = false
    @State private var messageVisible = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Back button row
                HStack {
                    Button {
                        HapticManager.shared.soft()
                        onBack()
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.body.weight(.semibold))
                            .themeText(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(Text("Back"))
                    Spacer()
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.top, Spacing.small)

                Spacer().frame(height: 24)

                // Title: "thanks, [name]." — 26pt bold (consistent)
                Text(appLocalizedString(Localizable.onboardingFlowSummaryTitle, arguments: name))
                    .font(.system(size: 26, weight: .bold))
                    .themeText(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 8)

                Spacer().frame(height: 8)

                // Subtitle — primary color, bigger, prominent
                Text(appLocalizedString(Localizable.onboardingFlowSummarySubtitle))
                    .font(.system(size: 17, weight: .regular))
                    .themeText(.primary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .opacity(isVisible ? 1 : 0)

                Spacer().frame(height: 32)

                // Summary cards
                VStack(spacing: 16) {
                    SummaryCardView(
                        label: appLocalizedString(Localizable.onboardingFlowSummaryWhereToGo),
                        emoji: vision?.emoji ?? "✨",
                        value: vision?.localizedTitle ?? "-"
                    )
                    .opacity(card1Visible ? 1 : 0)
                    .offset(y: card1Visible ? 0 : 12)

                    SummaryCardView(
                        label: appLocalizedString(Localizable.onboardingFlowSummaryWhereNow),
                        emoji: feeling?.emoji ?? "🔄",
                        value: feeling?.localizedTitle ?? "-"
                    )
                    .opacity(card2Visible ? 1 : 0)
                    .offset(y: card2Visible ? 0 : 12)

                    SummaryCardView(
                        label: appLocalizedString(Localizable.onboardingFlowSummaryStanding),
                        emoji: blocker?.emoji ?? "💭",
                        value: blocker?.localizedTitle ?? "-"
                    )
                    .opacity(card3Visible ? 1 : 0)
                    .offset(y: card3Visible ? 0 : 12)
                }
                .padding(.horizontal, Spacing.large)

                Spacer().frame(height: 28)

                // Personalized message — primary color, bigger, prominent
                Text(appLocalizedString(Localizable.onboardingFlowSummaryMessage, arguments: name))
                    .font(.system(size: 17, weight: .regular))
                    .themeText(.primary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .opacity(messageVisible ? 1 : 0)
                    .offset(y: messageVisible ? 0 : 8)

                Spacer()

                // Continue button
                OnboardingPrimaryButton(
                    appLocalizedString(Localizable.onboardingFlowContinue),
                    action: { onContinue() }
                )
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.large)
                .opacity(messageVisible ? 1 : 0)
                .offset(y: messageVisible ? 0 : 12)
            }
        }
        .onAppear {
            HapticManager.shared.gentle()
            startAnimations()
        }
    }

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
            isVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
            card1Visible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            card2Visible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.0)) {
            card3Visible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.4)) {
            messageVisible = true
        }
    }
}

// MARK: - Summary Card

private struct SummaryCardView: View {
    let label: String
    let emoji: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pill badge label
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.theme.backgroundTertiary)
                )

            // Emoji + value
            HStack(spacing: 12) {
                Text(emoji)
                    .font(.system(size: 22))

                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .themeText(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                .fill(Color.theme.backgroundSecondary)
        )
    }
}

#Preview {
    JourneySummaryView(
        name: "Paul",
        vision: .trustingMyselfMore,
        feeling: .hardToExplain,
        blocker: .noClearAnswer,
        onBack: {},
        onContinue: {}
    )
    .environment(\.theme, Theme())
}

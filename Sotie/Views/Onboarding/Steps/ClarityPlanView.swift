//
//  ClarityPlanView.swift
//  Sotie
//
//  Screen 28: "[name], your will have a clearer mind by [date+7]"
//  Hero card with target date + stat tiles + total hours invested,
//  followed by 3 method cards: private reflection, guided reflection,
//  and journal-that-remembers. Scrollable.
//

import SwiftUI

struct ClarityPlanView: View {
    let name: String
    let targetDate: Date
    let onContinue: () -> Void

    @State private var headerVisible = false
    @State private var card1Visible = false
    @State private var card2Visible = false
    @State private var card3Visible = false
    @State private var buttonVisible = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Spacing.medium) {
                        Spacer().frame(height: 40)

                        // Hero card — date + stats
                        heroCard
                            .opacity(headerVisible ? 1 : 0)
                            .offset(y: headerVisible ? 0 : 12)

                        // Section label
                        Text(appLocalizedString(Localizable.onboardingFlowPlanHowWellGetThere))
                            .font(.system(size: 18, weight: .semibold))
                            .themeText(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Spacing.medium)
                            .opacity(card1Visible ? 1 : 0)

                        // Method cards (3)
                        methodCard(
                            emoji: "✍️",
                            title: appLocalizedString(Localizable.onboardingFlowPlanMethod1Title),
                            body: appLocalizedString(Localizable.onboardingFlowPlanMethod1Body)
                        )
                        .opacity(card1Visible ? 1 : 0)
                        .offset(y: card1Visible ? 0 : 12)

                        methodCard(
                            emoji: "🪞",
                            title: appLocalizedString(Localizable.onboardingFlowPlanMethod2Title),
                            body: appLocalizedString(Localizable.onboardingFlowPlanMethod2Body)
                        )
                        .opacity(card2Visible ? 1 : 0)
                        .offset(y: card2Visible ? 0 : 12)

                        methodCard(
                            emoji: "📓",
                            title: appLocalizedString(Localizable.onboardingFlowPlanMethod3Title),
                            body: appLocalizedString(Localizable.onboardingFlowPlanMethod3Body)
                        )
                        .opacity(card3Visible ? 1 : 0)
                        .offset(y: card3Visible ? 0 : 12)

                        Spacer().frame(height: Spacing.large)
                    }
                    .padding(.horizontal, Spacing.large)
                }

                // Continue button
                OnboardingPrimaryButton(
                    appLocalizedString(Localizable.onboardingFlowContinue),
                    action: { onContinue() }
                )
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.xLarge)
                .opacity(buttonVisible ? 1 : 0)
                .offset(y: buttonVisible ? 0 : 12)
            }
        }
        .onAppear {
            HapticManager.shared.gentle()
            startAnimations()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(spacing: Spacing.medium) {
            // Headline
            Text(appLocalizedString(Localizable.onboardingFlowPlanHeroHeadline, arguments: name))
                .font(.system(size: 18, weight: .semibold))
                .themeText(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.medium)

            // Date pill
            Text(formattedTargetDate)
                .font(.system(size: 22, weight: .bold))
                .themeText(.primary)
                .padding(.horizontal, Spacing.large)
                .padding(.vertical, Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.theme.backgroundTertiary)
                )

            // Stat tiles (3)
            HStack(spacing: 10) {
                statTile(
                    emoji: "📓",
                    label: appLocalizedString(Localizable.onboardingFlowPlanStatReflections)
                )
                statTile(
                    emoji: "🌅",
                    label: appLocalizedString(Localizable.onboardingFlowPlanStatMornings)
                )
                statTile(
                    emoji: "💡",
                    label: appLocalizedString(Localizable.onboardingFlowPlanStatInsights)
                )
            }

            // Total invested pill
            HStack(spacing: 6) {
                Text("⏳")
                    .font(.system(size: 15))

                Text(appLocalizedString(Localizable.onboardingFlowPlanInvested))
                    .font(.system(size: 14, weight: .medium))
                    .themeText(.secondary)
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.theme.backgroundTertiary)
            )
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.theme.backgroundSecondary)
        )
    }

    // MARK: - Method card

    private func methodCard(emoji: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .themeText(.primary)
            }

            Text(body)
                .font(.system(size: 14, weight: .regular))
                .themeText(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.theme.backgroundSecondary)
        )
    }

    // MARK: - Stat tile

    private func statTile(emoji: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 18))

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .themeText(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.theme.backgroundTertiary)
        )
    }

    // MARK: - Formatting

    /// Locale-aware date — uses the user's selected app language and renders
    /// the date in lowercase to match the onboarding tone. The format template
    /// "MMMd, yyyy" lets the system choose locale-appropriate ordering and
    /// abbreviations (e.g. "may 11, 2026" / "11 мая 2026" / "2026年5月11日").
    private var formattedTargetDate: String {
        let formatter = Foundation.DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd, yyyy")
        return formatter.string(from: targetDate).lowercased(with: LanguageManager.shared.locale)
    }

    // MARK: - Animations

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
            headerVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            card1Visible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            HapticManager.shared.light()
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.0)) {
            card2Visible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            HapticManager.shared.light()
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.3)) {
            card3Visible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            HapticManager.shared.light()
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.7)) {
            buttonVisible = true
        }
    }
}

#Preview {
    ClarityPlanView(
        name: "Paul",
        targetDate: Date().addingTimeInterval(7 * 86400),
        onContinue: {}
    )
    .environment(\.theme, Theme())
}

//
//  HopeScreenView.swift
//  Sotie
//
//  Screen 9: "it doesn't have to be this way"
//  Reassurance/hope screen with smiley emoji centered + staggered text.
//  Uses split tap zones (left = back, right = forward).
//  Personalized: "let's build a plan for [name]"
//

import SwiftUI

struct HopeScreenView: View {
    let name: String
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var emojiVisible = false
    @State private var line1Visible = false
    @State private var line2Visible = false
    @State private var line3Visible = false
    @State private var bottomVisible = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            // Split tap zones
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.shared.soft()
                        onBack()
                    }
                    .frame(maxWidth: .infinity)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.shared.light()
                        onContinue()
                    }
                    .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea()

            // Content
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: 80)

                // Emoji — centered, same 180pt as value prop screens
                HStack {
                    Spacer()
                    LottieEmojiView(name: "smiley_emoji_2", size: 180)
                        .opacity(emojiVisible ? 1 : 0)
                        .scaleEffect(emojiVisible ? 1 : 0.8)
                    Spacer()
                }

                Spacer().frame(height: 48)

                // Line 1: "it doesn't have to be this way"
                Text(appLocalizedString(Localizable.onboardingFlowHopeLine1))
                    .font(.system(size: 22, weight: .medium))
                    .themeText(.primary)
                    .lineSpacing(4)
                    .opacity(line1Visible ? 1 : 0)
                    .offset(y: line1Visible ? 0 : 8)

                Spacer().frame(height: 24)

                // Line 2: "do you have just 5 minutes for your clarity each day?"
                buildLine2()
                    .lineSpacing(4)
                    .opacity(line2Visible ? 1 : 0)
                    .offset(y: line2Visible ? 0 : 8)

                Spacer().frame(height: 24)

                // Line 3: "let's build a plan for you"
                buildLine3()
                    .lineSpacing(4)
                    .opacity(line3Visible ? 1 : 0)
                    .offset(y: line3Visible ? 0 : 8)

                Spacer()

                TapToContinueIndicator()
                    .opacity(bottomVisible ? 1 : 0)
                    .offset(y: bottomVisible ? 0 : 8)
                    .padding(.bottom, Spacing.xLarge)
            }
            .padding(.horizontal, Spacing.large)
        }
        .onAppear {
            HapticManager.shared.gentle()
            startAnimations()
        }
    }

    // MARK: - Text Builders

    private func buildLine2() -> some View {
        DoubleHighlightedText(
            appLocalizedString(Localizable.onboardingFlowHopeLine2),
            highlight1: appLocalizedString(Localizable.onboardingFlowHopeLine2Highlight1),
            highlight2: appLocalizedString(Localizable.onboardingFlowHopeLine2Highlight2),
            font: .system(size: 22, weight: .semibold),
            highlightFont: .system(size: 22, weight: .bold)
        )
    }

    private func buildLine3() -> some View {
        // The phrase is a standalone "let's build your plan" - no name placeholder
        // because inflected languages (RU/DE/IT/ES) can't substitute a fallback
        // pronoun cleanly into a "for %@" slot.
        Text(appLocalizedString(Localizable.onboardingFlowHopeLine3))
            .font(.system(size: 22, weight: .medium))
            .themeText(.primary)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Animation Sequencing
    // Matches ValuePropView pacing: emoji 0.2s → headline 0.6s → lines stagger 0.6s apart

    private func startAnimations() {
        // Emoji bounces in
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.2)) {
            emojiVisible = true
        }

        // Line 1 (matches headline timing from VP screens)
        withAnimation(.easeOut(duration: 0.7).delay(0.6)) {
            line1Visible = true
        }

        // Line 2 (stagger 0.6s like body lines in VP)
        withAnimation(.easeOut(duration: 0.6).delay(1.2)) {
            line2Visible = true
        }

        // Line 3 (another 0.6s stagger)
        withAnimation(.easeOut(duration: 0.6).delay(1.8)) {
            line3Visible = true
        }

        // Bottom indicator (0.5s after last line)
        withAnimation(.easeOut(duration: 0.5).delay(2.3)) {
            bottomVisible = true
        }
    }
}

#Preview {
    HopeScreenView(name: "Paul", onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

//
//  ThankYouView.swift
//  Sotie
//
//  Screen 18: "thank you for your honesty, [name]."
//  Text-only storytelling screen with staggered reveal.
//  Uses split tap zones (left = back, right = forward).
//  Highlights: "coming back" and "clarity".
//

import SwiftUI

struct ThankYouView: View {
    let name: String
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var line1Visible = false
    @State private var line2Visible = false
    @State private var line3Visible = false
    @State private var line4Visible = false
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
                    .frame(height: 100)

                // Line 1: "thank you for your honesty, [name]."
                buildLine1()
                    .lineSpacing(4)
                    .opacity(line1Visible ? 1 : 0)
                    .offset(y: line1Visible ? 0 : 8)

                Spacer().frame(height: 32)

                // Line 2: "this isn't just a random thought."
                Text(appLocalizedString(Localizable.onboardingFlowThankYouLine2))
                    .font(.system(size: 22, weight: .medium))
                    .themeText(.primary)
                    .lineSpacing(4)
                    .opacity(line2Visible ? 1 : 0)
                    .offset(y: line2Visible ? 0 : 8)

                Spacer().frame(height: 24)

                // Line 3: "it keeps coming back because something underneath it still wants clarity."
                buildLine3()
                    .lineSpacing(4)
                    .opacity(line3Visible ? 1 : 0)
                    .offset(y: line3Visible ? 0 : 8)

                Spacer().frame(height: 24)

                // Line 4: "sotie listens first, reflects it back, and helps you understand what's really going on."
                Text(appLocalizedString(Localizable.onboardingFlowThankYouLine4))
                    .font(.system(size: 22, weight: .medium))
                    .themeText(.primary)
                    .lineSpacing(4)
                    .opacity(line4Visible ? 1 : 0)
                    .offset(y: line4Visible ? 0 : 8)

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

    private func buildLine1() -> some View {
        HighlightedText(
            appLocalizedString(Localizable.onboardingFlowThankYouLine1, arguments: name),
            highlight: appLocalizedString(Localizable.onboardingFlowThankYouLine1Highlight),
            highlightFont: .system(size: 26, weight: .bold)
        )
    }

    private func buildLine3() -> some View {
        HighlightedText(
            appLocalizedString(Localizable.onboardingFlowThankYouLine3),
            highlight: appLocalizedString(Localizable.onboardingFlowThankYouLine3Highlight),
            font: .system(size: 22, weight: .medium),
            highlightFont: .system(size: 22, weight: .bold)
        )
    }

    // MARK: - Animation Sequencing
    // Matches ValuePropView pacing: headline 0.6s → lines stagger 0.6s apart

    private func startAnimations() {
        // Line 1 (headline)
        withAnimation(.easeOut(duration: 0.7).delay(0.3)) {
            line1Visible = true
        }

        // Line 2
        withAnimation(.easeOut(duration: 0.6).delay(0.9)) {
            line2Visible = true
        }

        // Line 3
        withAnimation(.easeOut(duration: 0.6).delay(1.5)) {
            line3Visible = true
        }

        // Line 4
        withAnimation(.easeOut(duration: 0.6).delay(2.1)) {
            line4Visible = true
        }

        // Bottom indicator (0.5s after last line)
        withAnimation(.easeOut(duration: 0.5).delay(2.6)) {
            bottomVisible = true
        }
    }
}

#Preview {
    ThankYouView(name: "Paul", onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

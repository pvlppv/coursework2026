//
//  ValuePropView.swift
//  Sotie
//
//  Screens 2 & 3: value proposition with Lottie emoji + staggered text reveal.
//  Uses Instagram-stories split tap zones (left = back, right = forward).
//

import SwiftUI

// MARK: - Configuration

struct ValuePropConfig {
    let lottieName: String
    let headline: AttributedString
    let subtitle: AttributedString?
    let bodyLines: [AttributedString]
}

extension ValuePropConfig {
    /// Screen 2: "ever have a thought that won't leave you alone?"
    static func screen2() -> ValuePropConfig {
        var headline = AttributedString(
            appLocalizedString(Localizable.onboardingFlowVP1Headline)
        )
        if let range = headline.range(of: appLocalizedString(Localizable.onboardingFlowVP1Highlight)) {
            headline[range].foregroundColor = Color.theme.textSecondary
        }

        let lines: [AttributedString] = [
            AttributedString(appLocalizedString(Localizable.onboardingFlowVP1Body1)),
            AttributedString(appLocalizedString(Localizable.onboardingFlowVP1Body2)),
            AttributedString(appLocalizedString(Localizable.onboardingFlowVP1Body3)),
        ]

        return ValuePropConfig(
            lottieName: "rolling_eyes_emoji",
            headline: headline,
            subtitle: nil,
            bodyLines: lines
        )
    }

    /// Screen 3: "sotie helps you understand what's underneath it"
    static func screen3() -> ValuePropConfig {
        var headline = AttributedString(
            appLocalizedString(Localizable.onboardingFlowVP2Headline)
        )
        if let range = headline.range(of: appLocalizedString(Localizable.onboardingFlowVP2Highlight)) {
            headline[range].foregroundColor = Color.theme.textSecondary
        }

        var subtitle = AttributedString(
            appLocalizedString(Localizable.onboardingFlowVP2Subtitle)
        )
        if let range = subtitle.range(of: appLocalizedString(Localizable.onboardingFlowVP2SubtitleHighlight)) {
            subtitle[range].foregroundColor = Color.theme.textSecondary
        }

        let line1 = AttributedString(appLocalizedString(Localizable.onboardingFlowVP2Body1))
        let line2 = AttributedString(appLocalizedString(Localizable.onboardingFlowVP2Body2))
        var line3 = AttributedString(appLocalizedString(Localizable.onboardingFlowVP2Body3))
        if let range = line3.range(of: appLocalizedString(Localizable.onboardingFlowVP2Body3Highlight)) {
            line3[range].foregroundColor = Color.theme.textSecondary
        }

        return ValuePropConfig(
            lottieName: "star_strike_emoji",
            headline: headline,
            subtitle: subtitle,
            bodyLines: [line1, line2, line3]
        )
    }
}

// MARK: - View

struct ValuePropView: View {
    let config: ValuePropConfig
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var emojiVisible = false
    @State private var headlineVisible = false
    @State private var subtitleVisible = false
    @State private var bodyLineVisibility: [Bool] = []
    @State private var bottomVisible = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            // Split tap zones: left = back, right = forward
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

                // Lottie emoji — large, centered like reference
                HStack {
                    Spacer()
                    LottieEmojiView(name: config.lottieName, size: 180)
                        .opacity(emojiVisible ? 1 : 0)
                        .scaleEffect(emojiVisible ? 1 : 0.8)
                    Spacer()
                }

                Spacer()
                    .frame(height: 48)

                // Headline
                Text(config.headline)
                    .font(.system(size: 24, weight: .semibold))
                    .lineSpacing(4)
                    .themeText(.primary)
                    .multilineTextAlignment(.leading)
                    .opacity(headlineVisible ? 1 : 0)
                    .offset(y: headlineVisible ? 0 : 10)

                // Subtitle
                if let subtitle = config.subtitle {
                    Spacer().frame(height: 28)

                    Text(subtitle)
                        .font(.system(size: 20, weight: .medium))
                        .lineSpacing(3)
                        .themeText(.primary)
                        .multilineTextAlignment(.leading)
                        .opacity(subtitleVisible ? 1 : 0)
                        .offset(y: subtitleVisible ? 0 : 8)
                }

                // Body lines (staggered reveal)
                if !config.bodyLines.isEmpty {
                    Spacer().frame(height: 28)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(config.bodyLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 18, weight: .regular))
                                .lineSpacing(3)
                                .themeText(.primary)
                                .multilineTextAlignment(.leading)
                                .opacity(lineVisible(at: index) ? 1 : 0)
                                .offset(y: lineVisible(at: index) ? 0 : 6)
                        }
                    }
                }

                Spacer()

                TapToContinueIndicator()
                    .opacity(bottomVisible ? 1 : 0)
                    .offset(y: bottomVisible ? 0 : 8)
                    .padding(.bottom, Spacing.xLarge)
            }
            .padding(.horizontal, Spacing.large)
        }
        .onAppear {
            bodyLineVisibility = Array(repeating: false, count: config.bodyLines.count)
            startAnimations()
        }
    }

    // MARK: - Animation Sequencing

    private func lineVisible(at index: Int) -> Bool {
        guard index < bodyLineVisibility.count else { return false }
        return bodyLineVisibility[index]
    }

    private func startAnimations() {
        HapticManager.shared.gentle()

        // Emoji bounces in
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.2)) {
            emojiVisible = true
        }

        // Headline fades up — slower, more deliberate
        withAnimation(.easeOut(duration: 0.7).delay(0.6)) {
            headlineVisible = true
        }

        // Subtitle (if present)
        if config.subtitle != nil {
            withAnimation(.easeOut(duration: 0.6).delay(1.2)) {
                subtitleVisible = true
            }
        }

        // Body lines stagger — slower pace for reading rhythm
        let baseDelay: Double = config.subtitle != nil ? 1.6 : 1.2
        for index in config.bodyLines.indices {
            let delay = baseDelay + Double(index) * 0.4
            withAnimation(.easeOut(duration: 0.6).delay(delay)) {
                bodyLineVisibility[index] = true
            }
        }

        // Bottom indicator — appears after all text has settled
        let totalDelay = baseDelay + Double(config.bodyLines.count) * 0.4 + 0.5
        withAnimation(.easeOut(duration: 0.5).delay(totalDelay)) {
            bottomVisible = true
        }
    }
}

#Preview("Screen 2") {
    ValuePropView(
        config: .screen2(),
        onBack: {},
        onContinue: {}
    )
    .environment(\.theme, Theme())
}

#Preview("Screen 3") {
    ValuePropView(
        config: .screen3(),
        onBack: {},
        onContinue: {}
    )
    .environment(\.theme, Theme())
}

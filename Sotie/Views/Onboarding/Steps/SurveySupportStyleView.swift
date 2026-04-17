//
//  SurveySupportStyleView.swift
//  Sotie
//
//  Screen 19: "what kind of support feels best?"
//  Single-select with emoji-prefixed options.
//  Subtitle: "to make sure sotie fill right to you"
//  "right" is highlighted in the subtitle.
//

import SwiftUI

struct SurveySupportStyleView: View {
    @Binding var selection: AIReflectionSupportStyle?
    let progress: Double
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isVisible = false

    private var canContinue: Bool { selection != nil }

    /// Emojis for each support style option
    private func emoji(for style: AIReflectionSupportStyle) -> String {
        switch style {
        case .gentle: return "💛"
        case .warm: return "🫶"
        case .calming: return "😌"
        case .clear: return "💎"
        case .practical: return "📌"
        case .softButDirect: return "✨"
        }
    }

    /// Localized titles without emoji prefix (onboarding-specific keys)
    private func localizedTitle(for style: AIReflectionSupportStyle) -> String {
        switch style {
        case .gentle: return appLocalizedString(Localizable.onboardingFlowStyleGentle)
        case .warm: return appLocalizedString(Localizable.onboardingFlowStyleWarm)
        case .calming: return appLocalizedString(Localizable.onboardingFlowStyleCalming)
        case .clear: return appLocalizedString(Localizable.onboardingFlowStyleClear)
        case .practical: return appLocalizedString(Localizable.onboardingFlowStylePractical)
        case .softButDirect: return appLocalizedString(Localizable.onboardingFlowStyleSoftButDirect)
        }
    }

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Back button + progress bar
                HStack(spacing: 12) {
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

                    OnboardingProgressBar(progress: progress)
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.top, Spacing.small)

                Spacer().frame(height: 24)

                // Subtitle
                buildSubtitle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .opacity(isVisible ? 1 : 0)

                Spacer().frame(height: 8)

                // Question
                Text(appLocalizedString(Localizable.onboardingFlowStyleQuestion))
                    .font(.system(size: 26, weight: .bold))
                    .themeText(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 10)

                Spacer().frame(height: 24)

                // Options
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(AIReflectionSupportStyle.allCases) { style in
                            SurveyOptionRow(
                                emoji: emoji(for: style),
                                title: localizedTitle(for: style),
                                isSelected: selection == style
                            ) {
                                HapticManager.shared.light()
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selection = style
                                }
                                Analytics.onboardingSurveyAnswered(question: "supportStyle", answer: style.rawValue)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.large)
                }
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 8)

                Spacer()

                // Continue button
                OnboardingPrimaryButton(
                    appLocalizedString(Localizable.onboardingFlowContinue),
                    isEnabled: canContinue,
                    action: { onContinue() }
                )
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.large)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 12)
            }
        }
        .onAppear {
            HapticManager.shared.gentle()
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                isVisible = true
            }
        }
    }

    private func buildSubtitle() -> some View {
        HighlightedText(
            appLocalizedString(Localizable.onboardingFlowStyleSubtitle),
            highlight: appLocalizedString(Localizable.onboardingFlowStyleSubtitleHighlight),
            font: .system(size: 14, weight: .regular),
            highlightFont: .system(size: 14, weight: .bold),
            textColor: Color.theme.textSecondary,
            highlightColor: Color.theme.textPrimary
        )
    }
}

#Preview {
    @Previewable @State var selection: AIReflectionSupportStyle? = nil
    SurveySupportStyleView(selection: $selection, progress: 0.5, onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

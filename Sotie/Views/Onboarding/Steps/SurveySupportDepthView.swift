//
//  SurveySupportDepthView.swift
//  Sotie
//
//  Screen 20: "how deep should support go?"
//  Single-select with emoji-prefixed options.
//  Subtitle: "to make sure sotie fill right to you"
//

import SwiftUI

struct SurveySupportDepthView: View {
    @Binding var selection: AIReflectionSupportDepth?
    let progress: Double
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isVisible = false

    private var canContinue: Bool { selection != nil }

    /// Emojis for each support depth option
    private func emoji(for depth: AIReflectionSupportDepth) -> String {
        switch depth {
        case .calmMeFirst: return "🫶"
        case .helpMeUnderstandIt: return "🫶"
        case .askWhatMatters: return "😶"
        case .showMeThePattern: return "🌿"
        case .helpMeSeeItDifferently: return "✨"
        case .giveMeNextSteps: return "❤️"
        }
    }

    /// Localized titles without emoji prefix (onboarding-specific keys)
    private func localizedTitle(for depth: AIReflectionSupportDepth) -> String {
        switch depth {
        case .calmMeFirst: return appLocalizedString(Localizable.onboardingFlowDepthCalmMeFirst)
        case .helpMeUnderstandIt: return appLocalizedString(Localizable.onboardingFlowDepthHelpMeUnderstandIt)
        case .askWhatMatters: return appLocalizedString(Localizable.onboardingFlowDepthAskWhatMatters)
        case .showMeThePattern: return appLocalizedString(Localizable.onboardingFlowDepthShowMeThePattern)
        case .helpMeSeeItDifferently: return appLocalizedString(Localizable.onboardingFlowDepthHelpMeSeeItDifferently)
        case .giveMeNextSteps: return appLocalizedString(Localizable.onboardingFlowDepthGiveMeNextSteps)
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
                Text(appLocalizedString(Localizable.onboardingFlowDepthQuestion))
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
                        ForEach(AIReflectionSupportDepth.allCases) { depth in
                            SurveyOptionRow(
                                emoji: emoji(for: depth),
                                title: localizedTitle(for: depth),
                                isSelected: selection == depth
                            ) {
                                HapticManager.shared.light()
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selection = depth
                                }
                                Analytics.onboardingSurveyAnswered(question: "supportDepth", answer: depth.rawValue)
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
    @Previewable @State var selection: AIReflectionSupportDepth? = nil
    SurveySupportDepthView(selection: $selection, progress: 0.6, onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

//
//  SurveyVisionView.swift
//  Sotie
//
//  Screen 12: "thinking bigger, what would a clearer mind look like for you?"
//  Single-select with emoji-prefixed options.
//  Shows progress bar, back arrow, and Continue button.
//

import SwiftUI

struct SurveyVisionView: View {
    @Binding var selection: OnboardingVision?
    let progress: Double
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isVisible = false

    private var canContinue: Bool { selection != nil }

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Back button + progress bar row
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

                // Question with "clearer mind" highlighted
                buildQuestion()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 10)

                Spacer().frame(height: 24)

                // Options
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(OnboardingVision.allCases) { vision in
                            SurveyOptionRow(
                                emoji: vision.emoji,
                                title: vision.localizedTitle,
                                isSelected: selection == vision
                            ) {
                                HapticManager.shared.light()
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selection = vision
                                }
                                Analytics.onboardingSurveyAnswered(question: "vision", answer: vision.rawValue)
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

    // MARK: - Question Builder

    private func buildQuestion() -> some View {
        HighlightedText(
            appLocalizedString(Localizable.onboardingFlowVisionQuestion),
            highlight: appLocalizedString(Localizable.onboardingFlowVisionQuestionHighlight)
        )
    }
}

#Preview {
    @Previewable @State var selection: OnboardingVision? = nil
    SurveyVisionView(selection: $selection, progress: 0.24, onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

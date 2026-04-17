//
//  SurveyFeelingView.swift
//  Sotie
//
//  Screen 14: "how does this thought feel right now?"
//  Single-select with emoji-prefixed options.
//  Shows progress bar, back arrow, and Continue button.
//  "feel" is highlighted in the question.
//

import SwiftUI

struct SurveyFeelingView: View {
    @Binding var selection: ThoughtFeeling?
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

                // Question with "feel" highlighted
                buildQuestion()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 10)

                Spacer().frame(height: 24)

                // Options
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(ThoughtFeeling.allCases) { feeling in
                            SurveyOptionRow(
                                emoji: feeling.emoji,
                                title: feeling.localizedTitle,
                                isSelected: selection == feeling
                            ) {
                                HapticManager.shared.light()
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selection = feeling
                                }
                                Analytics.onboardingSurveyAnswered(question: "feeling", answer: feeling.rawValue)
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

    private func buildQuestion() -> some View {
        HighlightedText(
            appLocalizedString(Localizable.onboardingFlowFeelingQuestion),
            highlight: appLocalizedString(Localizable.onboardingFlowFeelingQuestionHighlight)
        )
    }
}

#Preview {
    @Previewable @State var selection: ThoughtFeeling? = nil
    SurveyFeelingView(selection: $selection, progress: 0.55, onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

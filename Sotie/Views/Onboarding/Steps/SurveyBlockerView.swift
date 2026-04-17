//
//  SurveyBlockerView.swift
//  Sotie
//
//  Screen 15: "what's the main thing that gets in the way?"
//  Single-select with emoji-prefixed options.
//  "main thing" is highlighted in the question.
//

import SwiftUI

struct SurveyBlockerView: View {
    @Binding var selection: ThoughtBlocker?
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

                // Question with "main thing" highlighted
                buildQuestion()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 10)

                Spacer().frame(height: 24)

                // Options
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(ThoughtBlocker.allCases) { blocker in
                            SurveyOptionRow(
                                emoji: blocker.emoji,
                                title: blocker.localizedTitle,
                                isSelected: selection == blocker
                            ) {
                                HapticManager.shared.light()
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selection = blocker
                                }
                                Analytics.onboardingSurveyAnswered(question: "blocker", answer: blocker.rawValue)
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
            appLocalizedString(Localizable.onboardingFlowBlockerQuestion),
            highlight: appLocalizedString(Localizable.onboardingFlowBlockerQuestionHighlight)
        )
    }
}

#Preview {
    @Previewable @State var selection: ThoughtBlocker? = nil
    SurveyBlockerView(selection: $selection, progress: 0.70, onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

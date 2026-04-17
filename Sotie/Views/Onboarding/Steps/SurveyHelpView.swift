//
//  SurveyHelpView.swift
//  Sotie
//
//  Screen 17: "what would help right now?"
//  Single-select with emoji-prefixed options.
//  "help" is highlighted in the question.
//

import SwiftUI

struct SurveyHelpView: View {
    @Binding var selection: ThoughtHelp?
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

                // Question with "help" highlighted
                buildQuestion()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 10)

                Spacer().frame(height: 24)

                // Options
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(ThoughtHelp.allCases) { help in
                            SurveyOptionRow(
                                emoji: help.emoji,
                                title: help.localizedTitle,
                                isSelected: selection == help
                            ) {
                                HapticManager.shared.light()
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selection = help
                                }
                                Analytics.onboardingSurveyAnswered(question: "help", answer: help.rawValue)
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
            appLocalizedString(Localizable.onboardingFlowHelpQuestion),
            highlight: appLocalizedString(Localizable.onboardingFlowHelpQuestionHighlight)
        )
    }
}

#Preview {
    @Previewable @State var selection: ThoughtHelp? = nil
    SurveyHelpView(selection: $selection, progress: 1.0, onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

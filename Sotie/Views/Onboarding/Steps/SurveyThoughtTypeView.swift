//
//  SurveyThoughtTypeView.swift
//  Sotie
//
//  Screen 6: "what kind of thought keeps coming back?"
//  Single-select survey with emoji-prefixed options.
//  Shows explicit back button + Continue button.
//

import SwiftUI

struct SurveyThoughtTypeView: View {
    @Binding var selection: ThoughtType?
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isVisible = false

    private var canContinue: Bool { selection != nil }

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Back button row
                HStack {
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
                    Spacer()
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.top, Spacing.small)

                Spacer().frame(height: 24)

                // Question - "thought" highlighted
                buildQuestion()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 10)

                Spacer().frame(height: 24)

                // Options
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(ThoughtType.allCases) { type in
                            SurveyOptionRow(
                                emoji: type.emoji,
                                title: type.localizedTitle,
                                isSelected: selection == type
                            ) {
                                HapticManager.shared.light()
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selection = type
                                }
                                Analytics.onboardingSurveyAnswered(question: "thoughtType", answer: type.rawValue)
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
            appLocalizedString(Localizable.onboardingFlowSurveyThoughtQuestion),
            highlight: appLocalizedString(Localizable.onboardingFlowSurveyThoughtQuestionHighlight)
        )
    }
}

#Preview {
    @Previewable @State var selection: ThoughtType? = nil
    SurveyThoughtTypeView(selection: $selection, onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

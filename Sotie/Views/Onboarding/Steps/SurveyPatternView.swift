//
//  SurveyPatternView.swift
//  Sotie
//
//  Screen 7: "how often does it come back?"
//  Combined frequency + duration in a single question.
//  Each option encodes both (e.g. "all the time and stays forever").
//  Shows explicit back button + Continue button.
//

import SwiftUI

struct SurveyPatternView: View {
    @Binding var selection: ThoughtPattern?
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

                // Question — consistent 26pt bold
                Text(appLocalizedString(Localizable.onboardingFlowSurveyPatternQuestion))
                    .font(.system(size: 26, weight: .bold))
                    .themeText(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 10)

                Spacer().frame(height: 24)

                // Options
                VStack(spacing: 10) {
                    ForEach(ThoughtPattern.allCases) { pattern in
                        SurveyOptionRow(
                            emoji: pattern.emoji,
                            title: pattern.localizedTitle,
                            isSelected: selection == pattern
                        ) {
                            HapticManager.shared.light()
                            withAnimation(.easeOut(duration: 0.2)) {
                                selection = pattern
                            }
                            Analytics.onboardingSurveyAnswered(question: "thoughtPattern", answer: pattern.rawValue)
                        }
                    }
                }
                .padding(.horizontal, Spacing.large)
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
}

#Preview {
    @Previewable @State var selection: ThoughtPattern? = nil
    SurveyPatternView(selection: $selection, onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

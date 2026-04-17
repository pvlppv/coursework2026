//
//  SurveyGoalsView.swift
//  Sotie
//
//  Screen 11: "what do you want to achieve with sotie?"
//  Multi-select (up to 3) with emoji-prefixed options.
//  Shows progress bar, back arrow, and Continue button.
//

import SwiftUI

struct SurveyGoalsView: View {
    @Binding var selection: Set<OnboardingGoal>
    let progress: Double
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isVisible = false

    private let maxSelections = 3

    private var canContinue: Bool { !selection.isEmpty }

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

                // Question
                VStack(alignment: .leading, spacing: 6) {
                    Text(appLocalizedString(Localizable.onboardingFlowGoalQuestion))
                        .font(.system(size: 26, weight: .bold))
                        .themeText(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(appLocalizedString(Localizable.onboardingFlowGoalSubtitle))
                        .font(.system(size: 15, weight: .regular))
                        .themeText(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.large)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

                Spacer().frame(height: 24)

                // Options
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(OnboardingGoal.allCases) { goal in
                            SurveyOptionRow(
                                emoji: goal.emoji,
                                title: goal.localizedTitle,
                                isSelected: selection.contains(goal)
                            ) {
                                HapticManager.shared.selection()
                                withAnimation(.easeOut(duration: 0.2)) {
                                    toggleGoal(goal)
                                }
                                let joined = selection
                                    .map(\.rawValue)
                                    .sorted()
                                    .joined(separator: ",")
                                Analytics.onboardingSurveyAnswered(question: "goals", answer: joined)
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

    private func toggleGoal(_ goal: OnboardingGoal) {
        if selection.contains(goal) {
            selection.remove(goal)
        } else if selection.count < maxSelections {
            selection.insert(goal)
        }
    }
}

#Preview {
    @Previewable @State var selection: Set<OnboardingGoal> = []
    SurveyGoalsView(selection: $selection, progress: 0.33, onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

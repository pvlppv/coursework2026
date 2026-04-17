//
//  PersonalizedPlanView.swift
//  Sotie
//
//  Screen 13: Personalized plan cards based on screen 11 goal selections.
//  Cards are in a vertical list, each with a slight rotation for a playful
//  "tossed on desk" feel — all fully visible and scrollable.
//  Ends with bold "you're in the right place" section.
//  Shows back arrow and Continue button.
//

import SwiftUI

struct PersonalizedPlanView: View {
    let goals: [OnboardingGoal]
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isVisible = false
    @State private var cardsVisible: [Bool] = []
    @State private var footerVisible = false

    /// Alternating rotations for playful card positioning
    private let rotations: [Double] = [-1.5, 1.2, -0.8]

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

                Spacer().frame(height: 16)

                // Scrollable cards + footer
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                            GoalCardView(goal: goal)
                                .rotationEffect(.degrees(rotation(for: index)))
                                .opacity(cardVisible(at: index) ? 1 : 0)
                                .scaleEffect(cardVisible(at: index) ? 1 : 0.9)
                                .offset(y: cardVisible(at: index) ? 0 : 20)
                        }

                        // Footer: "you're in the right place"
                        VStack(spacing: 12) {
                            Text(appLocalizedString(Localizable.onboardingFlowPlanFooterTitle))
                                .font(.system(size: 26, weight: .bold))
                                .themeText(.primary)
                                .multilineTextAlignment(.center)

                            Text(appLocalizedString(Localizable.onboardingFlowPlanFooterBody))
                                .font(.system(size: 17, weight: .regular))
                                .themeText(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .padding(.horizontal, Spacing.medium)
                        .opacity(footerVisible ? 1 : 0)
                        .offset(y: footerVisible ? 0 : 12)
                    }
                    .padding(.horizontal, Spacing.large)
                    .padding(.bottom, 8)
                }

                // Continue button
                OnboardingPrimaryButton(
                    appLocalizedString(Localizable.onboardingFlowContinue),
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
            cardsVisible = Array(repeating: false, count: goals.count)
            startAnimations()
        }
    }

    // MARK: - Helpers

    private func rotation(for index: Int) -> Double {
        rotations[index % rotations.count]
    }

    private func cardVisible(at index: Int) -> Bool {
        guard index < cardsVisible.count else { return false }
        return cardsVisible[index]
    }

    private func startAnimations() {
        for index in goals.indices {
            let delay = 0.4 + Double(index) * 0.45
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78).delay(delay)) {
                cardsVisible[index] = true
            }
        }

        let footerDelay = 0.4 + Double(goals.count) * 0.45 + 0.6
        withAnimation(.easeOut(duration: 0.7).delay(footerDelay)) {
            footerVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(footerDelay)) {
            isVisible = true
        }
    }
}

// MARK: - Goal Card

private struct GoalCardView: View {
    let goal: OnboardingGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(goal.emoji)
                    .font(.system(size: 28))

                Text(goal.localizedTitle)
                    .font(.system(size: 20, weight: .bold))
                    .themeText(.primary)
            }

            Text(goal.localizedDescription)
                .font(.system(size: 15, weight: .regular))
                .themeText(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                .fill(Color.theme.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                .stroke(Color.theme.textPrimary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.theme.shadow.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    PersonalizedPlanView(
        goals: [.feelClearer, .stopReplayingThings, .understandMyFeelings],
        onBack: {},
        onContinue: {}
    )
    .environment(\.theme, Theme())
}

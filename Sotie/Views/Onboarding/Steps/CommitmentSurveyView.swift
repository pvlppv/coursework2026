//
//  CommitmentSurveyView.swift
//  Sotie
//
//  Screen 29: "so, how committed are you to building a clearer mind?"
//  Single-select with 5 levels — extremely / very / somewhat / a little / just trying.
//  Continue button enabled only after a selection is made.
//

import SwiftUI

struct CommitmentSurveyView: View {
    @Binding var selection: CommitmentLevel?
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var headerVisible = false
    @State private var optionsVisible = false
    @State private var buttonVisible = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with back button
                HStack {
                    Button {
                        HapticManager.shared.soft()
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .themeText(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, Spacing.small)

                // Headline block
                VStack(alignment: .leading, spacing: 8) {
                    Text(appLocalizedString(Localizable.onboardingFlowCommitmentLeadIn))
                        .font(.system(size: 17, weight: .medium))
                        .themeText(.tertiary)

                    Text(appLocalizedString(Localizable.onboardingFlowCommitmentQuestion))
                        .font(.system(size: 24, weight: .bold))
                        .themeText(.primary)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.large)
                .padding(.top, Spacing.medium)
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : 8)

                Spacer().frame(height: Spacing.large)

                // Options
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(CommitmentLevel.allCases) { level in
                            SurveyOptionRow(
                                emoji: level.emoji,
                                title: level.localizedTitle,
                                isSelected: selection == level
                            ) {
                                HapticManager.shared.light()
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selection = level
                                }
                                Analytics.onboardingSurveyAnswered(question: "commitment", answer: level.rawValue)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.large)
                }
                .opacity(optionsVisible ? 1 : 0)
                .offset(y: optionsVisible ? 0 : 8)

                Spacer()

                // Continue button - disabled until a level is selected
                OnboardingPrimaryButton(
                    appLocalizedString(Localizable.onboardingFlowContinue),
                    isEnabled: selection != nil,
                    action: { onContinue() }
                )
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.xLarge)
                .opacity(buttonVisible ? 1 : 0)
                .offset(y: buttonVisible ? 0 : 12)
            }
        }
        .onAppear {
            HapticManager.shared.gentle()
            startAnimations()
        }
    }

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
            headerVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(0.6)) {
            optionsVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.0)) {
            buttonVisible = true
        }
    }
}

#Preview {
    @Previewable @State var selection: CommitmentLevel? = nil
    CommitmentSurveyView(
        selection: $selection,
        onBack: {},
        onContinue: {}
    )
    .environment(\.theme, Theme())
}

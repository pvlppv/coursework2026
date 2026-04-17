//
//  PlanReadyView.swift
//  Sotie
//
//  Screen 27: "alright [name], your personal plan is ready."
//  Standard theme background with a filled checkmark badge,
//  the headline, and a "see my plan" button.
//

import SwiftUI

struct PlanReadyView: View {
    let name: String
    let onContinue: () -> Void

    @State private var checkVisible = false
    @State private var headlineVisible = false
    @State private var buttonVisible = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Filled checkmark circle
                ZStack {
                    Circle()
                        .fill(Color.theme.buttonBackground)
                        .frame(width: 120, height: 120)

                    Image(systemName: "checkmark")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(Color.theme.buttonText)
                }
                .opacity(checkVisible ? 1 : 0)
                .scaleEffect(checkVisible ? 1 : 0.8)

                Spacer().frame(height: 40)

                // Headline
                Text(appLocalizedString(Localizable.onboardingFlowPlanReadyHeadline, arguments: name))
                    .font(.system(size: 26, weight: .bold))
                    .themeText(.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.large)
                    .opacity(headlineVisible ? 1 : 0)
                    .offset(y: headlineVisible ? 0 : 8)

                Spacer()

                // "see my plan" button
                OnboardingPrimaryButton(
                    appLocalizedString(Localizable.onboardingFlowPlanReadyCTA),
                    action: { onContinue() }
                )
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.xLarge)
                .opacity(buttonVisible ? 1 : 0)
                .offset(y: buttonVisible ? 0 : 12)
            }
        }
        .onAppear {
            HapticManager.shared.success()
            startAnimations()
        }
    }

    private func startAnimations() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2)) {
            checkVisible = true
        }
        withAnimation(.easeOut(duration: 0.7).delay(0.7)) {
            headlineVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.3)) {
            buttonVisible = true
        }
    }
}

#Preview {
    PlanReadyView(name: "Paul", onContinue: {})
        .environment(\.theme, Theme())
}

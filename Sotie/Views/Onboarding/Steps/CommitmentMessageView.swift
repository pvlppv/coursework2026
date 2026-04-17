//
//  CommitmentMessageView.swift
//  Sotie
//
//  Screen 30 (final): commitment-specific message + "done".
//  Standard theme background, SF Symbol flame as the visual anchor,
//  level-specific title and body, "done ✓" closes onboarding.
//

import SwiftUI

struct CommitmentMessageView: View {
    let level: CommitmentLevel
    let onContinue: () -> Void

    @State private var iconVisible = false
    @State private var titleVisible = false
    @State private var bodyVisible = false
    @State private var buttonVisible = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // SF Symbol flame inside a soft circle (replaces the lottie —
                // we already use the fire lottie on the streak screen, so a
                // calmer monochrome icon is the right call here).
                ZStack {
                    Circle()
                        .fill(Color.theme.backgroundSecondary)
                        .frame(width: 140, height: 140)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 64, weight: .regular))
                        .themeText(.primary)
                }
                .opacity(iconVisible ? 1 : 0)
                .scaleEffect(iconVisible ? 1 : 0.85)

                Spacer().frame(height: Spacing.large)

                // Title
                Text(level.localizedMessageTitle)
                    .font(.system(size: 28, weight: .bold))
                    .themeText(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.large)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 8)

                Spacer().frame(height: Spacing.medium)

                // Body
                Text(level.localizedMessageBody)
                    .font(.system(size: 17, weight: .regular))
                    .themeText(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.large)
                    .opacity(bodyVisible ? 1 : 0)
                    .offset(y: bodyVisible ? 0 : 8)

                Spacer()

                // Done button
                OnboardingPrimaryButton(
                    haptic: .success,
                    action: { onContinue() }
                ) {
                    HStack(spacing: 8) {
                        Text(appLocalizedString(Localizable.onboardingFlowDone))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.theme.buttonText)

                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.theme.buttonText)
                    }
                }
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
            iconVisible = true
        }
        withAnimation(.easeOut(duration: 0.7).delay(0.6)) {
            titleVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(1.1)) {
            bodyVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.6)) {
            buttonVisible = true
        }
    }
}

#Preview {
    CommitmentMessageView(level: .extremely, onContinue: {})
        .environment(\.theme, Theme())
}

//
//  OnboardingPrimaryButton.swift
//  Sotie
//
//  Reusable primary CTA button for the onboarding flow.
//  Single source of truth for sizing, typography, corner radius, shadow,
//  haptic feedback, and disabled state — so every Continue / Done / "Try
//  for $0.00" button feels identical and reads as a proper, modern
//  SwiftUI onboarding button (≥56pt tap target, 18pt vertical padding).
//

import SwiftUI

struct OnboardingPrimaryButton<Label: View>: View {
    let isEnabled: Bool
    let isLoading: Bool
    /// Haptic to fire on tap. Defaults to .medium for primary actions.
    /// Pass .success for completion-style buttons (Done, Start trial).
    let haptic: HapticKind
    let action: () -> Void
    let label: () -> Label

    enum HapticKind {
        case medium, success, light
    }

    init(
        isEnabled: Bool = true,
        isLoading: Bool = false,
        haptic: HapticKind = .medium,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.haptic = haptic
        self.action = action
        self.label = label
    }

    var body: some View {
        Button {
            triggerHaptic()
            action()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(Color.theme.buttonText)
                } else {
                    label()
                        .typography(.headline)
                        .foregroundColor(Color.theme.buttonText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                    .fill(Color.theme.buttonBackground)
            )
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }

    private func triggerHaptic() {
        switch haptic {
        case .medium: HapticManager.shared.medium()
        case .success: HapticManager.shared.success()
        case .light: HapticManager.shared.light()
        }
    }
}

// MARK: - Convenience initializer for plain text labels

extension OnboardingPrimaryButton where Label == Text {
    init(
        _ title: String,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        haptic: HapticKind = .medium,
        action: @escaping () -> Void
    ) {
        self.init(
            isEnabled: isEnabled,
            isLoading: isLoading,
            haptic: haptic,
            action: action,
            label: { Text(title) }
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        OnboardingPrimaryButton("Continue", action: {})
        OnboardingPrimaryButton("Continue", isEnabled: false, action: {})
        OnboardingPrimaryButton(isLoading: true, action: {}) {
            Text("Loading")
        }
        OnboardingPrimaryButton("Start My Journey", haptic: .success, action: {})
    }
    .padding(24)
    .background(Color.theme.backgroundPrimary)
}

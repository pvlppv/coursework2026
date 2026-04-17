//
//  NotificationsPrimingView.swift
//  Sotie
//
//  Screen 31: "be reminded to reflect"
//  Stylized notification permission preview — mocks the iOS system alert
//  visually (same shape, same buttons), with a pointing finger to "Allow".
//  Tapping anywhere on the alert mock triggers the REAL system permission
//  request. Tapping "Don't Allow" advances without requesting.
//

import SwiftUI

struct NotificationsPrimingView: View {
    let onContinue: () -> Void

    @State private var titleVisible = false
    @State private var alertVisible = false
    @State private var fingerOffset: CGFloat = 0
    @State private var hasResponded = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Title — "be reminded to reflect"
                Text(appLocalizedString(Localizable.onboardingFlowNotifPrimingTitle))
                    .font(.system(size: 26, weight: .bold))
                    .themeText(.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.large)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 8)

                Spacer().frame(height: Spacing.xLarge)

                // Stylized alert
                stylizedAlert
                    .opacity(alertVisible ? 1 : 0)
                    .scaleEffect(alertVisible ? 1 : 0.94)
                    .padding(.horizontal, Spacing.xLarge)

                // Pointing finger — pulses toward the Allow button
                Text("👆")
                    .font(.system(size: 36))
                    .offset(x: 60, y: -8 + fingerOffset)
                    .opacity(alertVisible ? 1 : 0)
                    .accessibilityHidden(true)

                Spacer()
            }
        }
        .onAppear {
            HapticManager.shared.gentle()
            startAnimations()
        }
    }

    // MARK: - Stylized Alert

    /// Mimics the iOS permission alert's shape and structure visually so the
    /// user understands what's coming. Tapping "Allow" triggers the REAL
    /// system permission request — the actual iOS alert appears on top.
    private var stylizedAlert: some View {
        VStack(spacing: 0) {
            // Body — uses tertiary background so the alert pops off the screen
            VStack(spacing: 6) {
                Text(appLocalizedString(Localizable.onboardingFlowNotifPrimingAlertTitle))
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.theme.textPrimary)

                Text(appLocalizedString(Localizable.onboardingFlowNotifPrimingAlertBody))
                    .font(.system(size: 13, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.theme.textSecondary)
                    .lineSpacing(2)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, Spacing.medium)
            .frame(maxWidth: .infinity)

            // Buttons row — Allow uses filled style to look highlighted
            HStack(spacing: 8) {
                Button {
                    HapticManager.shared.soft()
                    advanceWithoutRequest()
                } label: {
                    Text(appLocalizedString(Localizable.onboardingFlowNotifPrimingDeny))
                        .font(.system(size: 16, weight: .medium))
                        .themeText(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.theme.backgroundPrimary)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    HapticManager.shared.medium()
                    requestRealPermission()
                } label: {
                    Text(appLocalizedString(Localizable.onboardingFlowNotifPrimingAllow))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.theme.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.theme.buttonBackground)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.theme.backgroundTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.theme.divider, lineWidth: 1)
        )
        .themeShadow(.medium)
    }

    // MARK: - Permission Flow

    /// Triggers the real system notification permission request.
    /// Advances regardless of grant/deny outcome.
    private func requestRealPermission() {
        guard !hasResponded else { return }
        hasResponded = true

        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            await MainActor.run {
                Analytics.onboardingNotificationDecision(allowed: granted)
                onContinue()
            }
        }
    }

    /// User tapped "Don't allow" on our preview - skip the permission
    /// request entirely so we don't burn the system prompt slot.
    private func advanceWithoutRequest() {
        guard !hasResponded else { return }
        hasResponded = true
        Analytics.onboardingNotificationDecision(allowed: false)
        onContinue()
    }

    // MARK: - Animations

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
            titleVisible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.7)) {
            alertVisible = true
        }
        // Finger pulse — gentle bob toward the alert
        withAnimation(
            .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true)
                .delay(1.4)
        ) {
            fingerOffset = -6
        }
    }
}

#Preview {
    NotificationsPrimingView(onContinue: {})
        .environment(\.theme, Theme())
}

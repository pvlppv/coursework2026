//
//  PressableButtonStyle.swift
//  Sotie
//

import SwiftUI

/// Rich press animation: depth shadow (vdavlivaniye) + two-beat haptic.
/// Used exclusively on primary action buttons (Go Deeper FAB).
///
/// Visual: scale 1.0 → 0.91 on press, spring overshoot on release.
/// Shadow: disappears on press (surface push-down effect), returns on release.
/// Haptic: soft on press (beat 1), medium on release (beat 2) — ~80ms apart.
struct PressableButtonStyle: ButtonStyle {
  @State private var scale: CGFloat = 1.0
  @State private var shadowOpacity: Double = 0.18
  @State private var shadowRadius: CGFloat = 10
  @State private var shadowY: CGFloat = 5
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      // Suppress SwiftUI's default button press dimming / highlight overlay
      .compositingGroup()
      .scaleEffect(scale)
      .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
      .onChange(of: configuration.isPressed) { _, pressed in
        guard isEnabled else { return }
        if pressed {
          withAnimation(.easeOut(duration: 0.08)) {
            scale = reduceMotion ? 1 : 0.91
            shadowOpacity = 0.03
            shadowRadius = 2
            shadowY = 1
          }
          HapticManager.shared.soft()
        } else {
          // Delay spring-back so the press-down state is always visible on fast taps
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.48)) {
              scale = 1.0
              shadowOpacity = 0.18
              shadowRadius = 10
              shadowY = 5
            }
            // Beat 2: ~80ms after beat 1 — two distinct haptic events
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
              HapticManager.shared.medium()
            }
          }
        }
      }
  }
}

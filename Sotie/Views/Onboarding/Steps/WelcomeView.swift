//
//  WelcomeView.swift
//  Sotie
//
//  Screen 1: "hey" — centered, soft fade-up, full-screen tap to advance.
//

import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    @State private var textVisible = false
    @State private var bottomVisible = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            // Full-screen tap zone (no back on first screen)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticManager.shared.light()
                    onContinue()
                }

            VStack(spacing: 0) {
                Spacer()

                Text(appLocalizedString(Localizable.onboardingFlowHey))
                    .font(.system(size: 38, weight: .bold, design: .default))
                    .themeText(.primary)
                    .opacity(textVisible ? 1 : 0)
                    .offset(y: textVisible ? 0 : 14)
                    .scaleEffect(textVisible ? 1 : 0.96)

                Spacer()

                TapToContinueIndicator()
                    .opacity(bottomVisible ? 1 : 0)
                    .offset(y: bottomVisible ? 0 : 8)
                    .padding(.horizontal, Spacing.large)
                    .padding(.bottom, Spacing.xLarge)
            }
        }
        .onAppear {
            HapticManager.shared.gentle()
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
                textVisible = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                bottomVisible = true
            }
        }
    }
}

#Preview {
    WelcomeView(onContinue: {})
        .environment(\.theme, Theme())
}

//
//  ProgressChartView.swift
//  Sotie
//
//  Screen 22: "thoughts get quieter when they're understood"
//  Shows onboarding_chart image + motivational text.
//  All text centered, generous spacing.
//  Uses split tap zones (text-only screen style).
//

import SwiftUI

struct ProgressChartView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var titleVisible = false
    @State private var chartVisible = false
    @State private var textVisible = false
    @State private var bottomVisible = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            // Split tap zones
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.shared.soft()
                        onBack()
                    }
                    .frame(maxWidth: .infinity)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.shared.light()
                        onContinue()
                    }
                    .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea()

            // Content — all centered
            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                // Title: 26pt bold (consistent)
                Text(appLocalizedString(Localizable.onboardingFlowChartTitle))
                    .font(.system(size: 26, weight: .bold))
                    .themeText(.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.large)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 8)

                Spacer().frame(height: 36)

                // Chart image
                Image("onboarding_chart")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, Spacing.medium)
                    .opacity(chartVisible ? 1 : 0)
                    .scaleEffect(chartVisible ? 1 : 0.95)

                Spacer().frame(height: 36)

                // Motivational text — centered
                Text(appLocalizedString(Localizable.onboardingFlowChartBody))
                    .font(.system(size: 22, weight: .medium))
                    .themeText(.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, Spacing.large)
                    .opacity(textVisible ? 1 : 0)
                    .offset(y: textVisible ? 0 : 8)

                Spacer()

                // "learn how sotie works →"
                HStack(spacing: 6) {
                    Text(appLocalizedString(Localizable.onboardingFlowChartCTA))
                        .typography(.bodyEmphasized)
                        .themeText(.secondary)

                    Image(systemName: "arrow.right")
                        .font(.body.weight(.semibold))
                        .themeText(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, Spacing.large)
                .opacity(bottomVisible ? 1 : 0)
                .offset(y: bottomVisible ? 0 : 8)
                .padding(.bottom, Spacing.xLarge)
            }
        }
        .onAppear {
            HapticManager.shared.gentle()
            startAnimations()
        }
    }

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.7).delay(0.3)) {
            titleVisible = true
        }
        withAnimation(.easeOut(duration: 0.8).delay(0.8)) {
            chartVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(1.6)) {
            textVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(2.2)) {
            bottomVisible = true
        }
    }
}

#Preview {
    ProgressChartView(onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

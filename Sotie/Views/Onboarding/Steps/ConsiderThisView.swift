//
//  ConsiderThisView.swift
//  Sotie
//
//  Screen 5: "alright [name], consider this..."
//  Bridge screen into the survey phase.
//  Uses the BlurRevealRenderer for a sacred, AI-response-like text reveal.
//  Split tap zones (left = back, right = forward).
//

import SwiftUI

struct ConsiderThisView: View {
    let name: String
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var revealStartDate: Date? = nil
    @State private var isRevealing = false
    @State private var revealComplete = false
    @State private var finalElapsed: Double = 100
    @State private var bottomVisible = false

    private let revealSpeed: Double = 0.9

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

            // Content — centered
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRevealing)) { timeline in
                let elapsed = revealComplete ? finalElapsed : computeElapsed(at: timeline.date)
                let renderer = BlurRevealRenderer(elapsedTime: elapsed)

                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 4) {
                        Text(appLocalizedString(Localizable.onboardingFlowConsiderLine1, arguments: name))
                            .font(.system(size: 28, weight: .bold))
                            .themeText(.primary)
                            .multilineTextAlignment(.center)

                        Text(appLocalizedString(Localizable.onboardingFlowConsiderLine2))
                            .font(.system(size: 28, weight: .bold))
                            .themeText(.primary)
                            .multilineTextAlignment(.center)
                    }
                    .textRenderer(renderer)

                    Spacer()

                    TapToContinueIndicator()
                        .opacity(bottomVisible ? 1 : 0)
                        .offset(y: bottomVisible ? 0 : 8)
                        .padding(.horizontal, Spacing.large)
                        .padding(.bottom, Spacing.xLarge)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            HapticManager.shared.gentle()

            // Start blur reveal after a brief pause
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                revealStartDate = Date()
                isRevealing = true
            }

            // Show bottom indicator after text has mostly revealed
            withAnimation(.easeOut(duration: 0.5).delay(1.8)) {
                bottomVisible = true
            }
        }
    }

    // MARK: - Elapsed Time

    private func computeElapsed(at date: Date) -> Double {
        guard let start = revealStartDate else { return 0 }
        let raw = date.timeIntervalSince(start) * revealSpeed

        // Check if reveal is complete
        let fullText = appLocalizedString(Localizable.onboardingFlowConsiderLine1, arguments: name)
            + appLocalizedString(Localizable.onboardingFlowConsiderLine2)
        let threshold = BlurRevealRenderer(elapsedTime: 0)
            .revealDuration(forCharacterCount: fullText.count)

        if raw >= threshold && !revealComplete {
            // Lock the final elapsed value and stop the timeline
            DispatchQueue.main.async {
                finalElapsed = raw
                revealComplete = true
                isRevealing = false
            }
        }

        return raw
    }
}

#Preview {
    ConsiderThisView(name: "Paul", onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}

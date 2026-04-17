//
//  EmpathyCalculationView.swift
//  Sotie
//
//  Screen 8: "Paul, you'll spend 2,184 hours this year replaying what happened"
//  Personalized empathy screen with animated counter for the hours number.
//  Lottie emoji centered. Split tap zones.
//

import SwiftUI

struct EmpathyCalculationView: View {
    let name: String
    let targetHours: Int
    let days: Int
    let verb: String
    let onBack: () -> Void
    let onContinue: () -> Void

    // Counter animation state
    @State private var displayedHours: Int = 0
    @State private var counterTimer: Timer?

    // Reveal states
    @State private var emojiVisible = false
    @State private var statsVisible = false
    @State private var daysVisible = false
    @State private var questionVisible = false
    @State private var bottomVisible = false

    private var formattedDisplayHours: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: displayedHours)) ?? "\(displayedHours)"
    }

    private var formattedDays: String {
        "\(days)"
    }

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

            // Content
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: 80)

                // Emoji — centered, oversized to match visual weight
                // (head explosion asset has more whitespace than other emojis)
                HStack {
                    Spacer()
                    LottieEmojiView(name: "emoji_head_explosion", size: 280)
                        .padding(.vertical, -40) // clip internal whitespace in the asset
                        .opacity(emojiVisible ? 1 : 0)
                        .scaleEffect(emojiVisible ? 1 : 0.8)
                    Spacer()
                }

                Spacer().frame(height: 48)

                // Stats block
                VStack(alignment: .leading, spacing: 6) {
                    // "Paul, you'll spend"
                    Text("\(name), \(appLocalizedString(Localizable.onboardingFlowEmpathyYoullSpend))")
                        .font(.system(size: 22, weight: .medium))
                        .themeText(.primary)

                    // "3 650 hours this year" — counter animated
                    HStack(spacing: 0) {
                        Text(formattedDisplayHours)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Color.theme.textSecondary)
                            .contentTransition(.numericText(value: Double(displayedHours)))

                        Text(" \(appLocalizedString(Localizable.onboardingFlowEmpathyHoursThisYear))")
                            .font(.system(size: 22, weight: .medium))
                            .themeText(.primary)
                    }

                    // Verb (dynamic)
                    Text(verb)
                        .font(.system(size: 22, weight: .medium))
                        .themeText(.primary)
                }
                .opacity(statsVisible ? 1 : 0)
                .offset(y: statsVisible ? 0 : 10)

                Spacer().frame(height: 28)

                // "that's 152 days" — appears well after counter finishes for impact
                HStack(spacing: 0) {
                    Text("\(appLocalizedString(Localizable.onboardingFlowEmpathyThats)) ")
                        .font(.system(size: 22, weight: .medium))
                        .themeText(.primary)

                    Text("\(formattedDays) \(appLocalizedString(Localizable.onboardingFlowEmpathyDays))")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color.theme.textSecondary)
                }
                .opacity(daysVisible ? 1 : 0)
                .offset(y: daysVisible ? 0 : 8)

                Spacer().frame(height: 28)

                // "how much of that time actually helps you feel clearer?"
                buildQuestionText()
                    .lineSpacing(4)
                    .opacity(questionVisible ? 1 : 0)
                    .offset(y: questionVisible ? 0 : 8)

                Spacer()

                TapToContinueIndicator()
                    .opacity(bottomVisible ? 1 : 0)
                    .offset(y: bottomVisible ? 0 : 8)
                    .padding(.bottom, Spacing.xLarge)
            }
            .padding(.horizontal, Spacing.large)
        }
        .onAppear {
            HapticManager.shared.gentle()
            startAnimations()
        }
        .onDisappear {
            counterTimer?.invalidate()
        }
    }

    // MARK: - Text Builder

    private func buildQuestionText() -> some View {
        HighlightedText(
            appLocalizedString(Localizable.onboardingFlowEmpathyQuestion),
            highlight: appLocalizedString(Localizable.onboardingFlowEmpathyQuestionHighlight),
            font: .system(size: 22, weight: .medium),
            highlightFont: .system(size: 22, weight: .bold)
        )
    }

    // MARK: - Animation Sequencing
    // Matches the deliberate pacing of ValuePropView (screens 2-3):
    // emoji 0.2s → first text 0.6s → stagger 0.6s between lines

    private func startAnimations() {
        // Emoji bounces in (same as VP screens)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.2)) {
            emojiVisible = true
        }

        // Stats block appears (matches headline timing)
        withAnimation(.easeOut(duration: 0.7).delay(0.6)) {
            statsVisible = true
        }

        // Start counter after stats are visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            startCounter()
        }
    }

    private func showPostCounterContent() {
        // "that's X days" — 0.8s pause after counter lands
        withAnimation(.easeOut(duration: 0.7).delay(0.8)) {
            daysVisible = true
        }

        // Question — 0.6s after days
        withAnimation(.easeOut(duration: 0.6).delay(1.4)) {
            questionVisible = true
        }

        // Bottom indicator — 0.5s after question
        withAnimation(.easeOut(duration: 0.5).delay(1.9)) {
            bottomVisible = true
        }
    }

    private func startCounter() {
        let totalDuration: Double = 1.8 // seconds for the count-up
        let steps = 40 // number of increments
        let interval = totalDuration / Double(steps)

        var currentStep = 0
        // Fire a soft haptic every Nth tick so the count-up feels physical
        // without overloading the Taptic engine. ~5 ticks total works out to
        // a "tick … tick … tick" cadence over ~1.8s.
        let hapticEveryNTicks = max(1, steps / 5)

        counterTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            currentStep += 1

            // Ease-out curve: fast start, slow finish
            let progress = Double(currentStep) / Double(steps)
            let easedProgress = 1.0 - pow(1.0 - progress, 3) // cubic ease-out

            withAnimation(.linear(duration: interval)) {
                displayedHours = Int(Double(targetHours) * easedProgress)
            }

            if currentStep % hapticEveryNTicks == 0 && currentStep < steps {
                HapticManager.shared.soft()
            }

            if currentStep >= steps {
                timer.invalidate()
                withAnimation(.linear(duration: 0.05)) {
                    displayedHours = targetHours
                }
                // Satisfying haptic at the end of count
                HapticManager.shared.medium()
                // Trigger post-counter reveals
                showPostCounterContent()
            }
        }
    }
}

#Preview {
    EmpathyCalculationView(
        name: "Paul",
        targetHours: 3650,
        days: 152,
        verb: "replaying what happened",
        onBack: {},
        onContinue: {}
    )
    .environment(\.theme, Theme())
}

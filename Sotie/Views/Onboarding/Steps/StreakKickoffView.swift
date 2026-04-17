//
//  StreakKickoffView.swift
//  Sotie
//
//  Screen 25 (final onboarding step): "1 day streak"
//  Celebrates the user's first reflection with a fire lottie, day-streak hero,
//  and the Mon-Sun day chip row. Triggers an immediate App Store review prompt
//  on appear so we capture sentiment at the peak moment.
//

import SwiftUI

struct StreakKickoffView: View {
    let onContinue: () -> Void

    @State private var fireVisible = false
    @State private var counterVisible = false
    @State private var labelVisible = false
    @State private var bodyVisible = false
    @State private var weekVisible = false
    @State private var buttonVisible = false
    @State private var reviewPromptScheduled = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                // Fire lottie — same 180pt standard as other emoji screens
                LottieEmojiView(name: "fire", size: 180)
                    .opacity(fireVisible ? 1 : 0)
                    .scaleEffect(fireVisible ? 1 : 0.85)

                Spacer().frame(height: 24)

                // Big "1"
                Text("1")
                    .font(.system(size: 88, weight: .bold))
                    .themeText(.primary)
                    .opacity(counterVisible ? 1 : 0)
                    .offset(y: counterVisible ? 0 : 8)

                Spacer().frame(height: 4)

                // "day streak"
                Text(appLocalizedString(Localizable.onboardingFlowStreakDayLabel))
                    .font(.system(size: 26, weight: .bold))
                    .themeText(.primary)
                    .opacity(labelVisible ? 1 : 0)
                    .offset(y: labelVisible ? 0 : 8)

                Spacer().frame(height: 16)

                // Motivational body
                Text(appLocalizedString(Localizable.onboardingFlowStreakBody))
                    .font(.system(size: 17, weight: .medium))
                    .themeText(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.large)
                    .opacity(bodyVisible ? 1 : 0)
                    .offset(y: bodyVisible ? 0 : 8)

                Spacer().frame(height: 36)

                // Week chip row
                weekRow
                    .padding(.horizontal, Spacing.large)
                    .opacity(weekVisible ? 1 : 0)
                    .offset(y: weekVisible ? 0 : 8)

                Spacer()

                // Continue button
                OnboardingPrimaryButton(
                    appLocalizedString(Localizable.onboardingFlowContinue),
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
            scheduleReviewPrompt()
        }
    }

    // MARK: - Week Row

    /// Mon-Sun chip row with today highlighted via filled black circle.
    private var weekRow: some View {
        let weekdaySymbols = Self.localizedShortWeekdays()
        let todayIndex = Self.todayWeekdayIndexMondayFirst()

        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 8) {
                    Text(weekdaySymbols[index])
                        .font(.system(size: 13, weight: .medium))
                        .themeText(.tertiary)

                    ZStack {
                        Circle()
                            .fill(index == todayIndex ? Color.theme.buttonBackground : Color.clear)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        index == todayIndex ? Color.clear : Color.theme.divider,
                                        lineWidth: 1.5
                                    )
                            )
                            .frame(width: 36, height: 36)

                        if index == todayIndex {
                            Text("1")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(Color.theme.buttonText)
                        } else {
                            Text("\(dayNumber(at: index, todayIndex: todayIndex))")
                                .font(.system(size: 15, weight: .medium))
                                .themeText(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Spacing.medium)
        .padding(.horizontal, Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.theme.divider, lineWidth: 1)
        )
    }

    /// Sequential day count (1 = today, 2 = tomorrow, etc.)
    /// Past days in the week get incrementing later numbers wrapping forward.
    private func dayNumber(at index: Int, todayIndex: Int) -> Int {
        let offset = (index - todayIndex + 7) % 7
        return offset + 1
    }

    // MARK: - Locale helpers

    /// Returns short weekday symbols starting with Monday (su/mo/tu/we/th/fr/sa style).
    /// Uses the calendar's veryShortStandaloneWeekdaySymbols for localization.
    private static func localizedShortWeekdays() -> [String] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2  // Monday
        // veryShortStandaloneWeekdaySymbols is Sun-first; rotate to Mon-first
        let raw = calendar.veryShortStandaloneWeekdaySymbols  // [Sun, Mon, ..., Sat]
        // Rotate so Mon is first
        let rotated = Array(raw[1...]) + [raw[0]]
        return rotated.map { $0.lowercased() }
    }

    /// 0 = Monday, 6 = Sunday.
    private static func todayWeekdayIndexMondayFirst() -> Int {
        let calendar = Calendar.current
        // Calendar.component(.weekday, ...) returns 1=Sun ... 7=Sat
        let weekday = calendar.component(.weekday, from: Date())
        // Convert to 0=Mon ... 6=Sun
        return (weekday + 5) % 7
    }

    // MARK: - Review Prompt

    /// Triggers the system review prompt on this celebratory screen.
    /// This is the peak emotional moment (streak 1) — prompt must fire 100%.
    /// Timing: 2.8s after appear, right after the Continue button settles in.
    private func scheduleReviewPrompt() {
        guard !reviewPromptScheduled else { return }
        reviewPromptScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            ReviewManager.shared.requestReviewForCelebration()
        }
    }

    // MARK: - Animations
    // Cadence: lottie spring 0.2s → counter 0.7s @ 0.6s → label/body stagger 0.6s apart

    private func startAnimations() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2)) {
            fireVisible = true
        }
        withAnimation(.easeOut(duration: 0.7).delay(0.6)) {
            counterVisible = true
        }
        // Synced "thump" with the counter landing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            HapticManager.shared.medium()
        }
        withAnimation(.easeOut(duration: 0.6).delay(1.1)) {
            labelVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(1.6)) {
            bodyVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(2.1)) {
            weekVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(2.6)) {
            buttonVisible = true
        }
    }
}

#Preview {
    StreakKickoffView(onContinue: {})
        .environment(\.theme, Theme())
}

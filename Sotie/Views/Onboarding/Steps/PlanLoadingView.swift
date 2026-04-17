//
//  PlanLoadingView.swift
//  Sotie
//
//  Screen 26: "building your reflection framework..."
//  Animated circular progress + step dots + rotating status text.
//  Auto-advances when progress reaches 100%.
//

import SwiftUI

struct PlanLoadingView: View {
    let onContinue: () -> Void

    /// Total time the loading sequence runs before auto-advancing.
    private let totalDuration: Double = 5.5

    /// Cumulative percent target at the END of each step. Variable chunks give
    /// the loading a natural rhythm rather than a constant +1 tick. Larger
    /// chunks during "discovery" steps, smaller during "settling" steps.
    private let phaseTargets: [Int] = [18, 42, 60, 84, 100]

    /// Status lines shown sequentially. Each line lights up while the dot
    /// for that step is active, then dims as we move to the next step.
    private let statusLines: [String] = [
        appLocalizedString(Localizable.onboardingFlowPlanLoadingStep1),
        appLocalizedString(Localizable.onboardingFlowPlanLoadingStep2),
        appLocalizedString(Localizable.onboardingFlowPlanLoadingStep3),
        appLocalizedString(Localizable.onboardingFlowPlanLoadingStep4),
        appLocalizedString(Localizable.onboardingFlowPlanLoadingStep5)
    ]

    @State private var progress: Double = 0
    @State private var displayedPercent: Int = 0
    @State private var currentStep: Int = 0
    @State private var hasAdvanced = false
    @State private var percentTimer: Timer?
    @State private var startTime: Date?

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Circular progress + percentage in center
                ZStack {
                    Circle()
                        .stroke(Color.theme.divider, lineWidth: 12)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.theme.textPrimary,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .transaction { $0.animation = nil }

                    Text("\(displayedPercent)%")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .themeText(.primary)
                        .transaction { $0.animation = nil }
                }
                .frame(width: 200, height: 200)

                Spacer().frame(height: 44)

                // Step dots
                HStack(spacing: 10) {
                    ForEach(0..<statusLines.count, id: \.self) { index in
                        Circle()
                            .fill(
                                index <= currentStep
                                    ? Color.theme.textPrimary
                                    : Color.theme.divider
                            )
                            .frame(width: 8, height: 8)
                            .scaleEffect(index == currentStep ? 1.3 : 1.0)
                            .animation(.easeOut(duration: 0.3), value: currentStep)
                    }
                }

                Spacer().frame(height: 32)

                // Rotating status text — primary color, larger and bolder
                Text(statusLines[currentStep])
                    .font(.system(size: 22, weight: .semibold))
                    .themeText(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.large)
                    .id(currentStep)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity.combined(with: .offset(y: -8))
                    ))

                Spacer()
            }
        }
        .onAppear {
            HapticManager.shared.gentle()
            startProgress()
        }
        .onDisappear {
            percentTimer?.invalidate()
            percentTimer = nil
        }
    }

    private func startProgress() {
        startTime = Date()
        displayedPercent = 0
        progress = 0
        currentStep = 0

        percentTimer?.invalidate()
        // ~60Hz tick — smooth enough for the ring, fast enough that the
        // percent reads as a natural counter without feeling robotic.
        percentTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            DispatchQueue.main.async {
                guard let start = startTime else { return }

                let elapsed = Date().timeIntervalSince(start)
                let t = min(elapsed / totalDuration, 1.0)

                // Figure out which phase we're in based on elapsed time.
                // Each phase gets an equal time slice; within the slice we
                // ease out so the percent jumps fast then settles, like a
                // real "thinking" indicator.
                let phaseCount = phaseTargets.count
                let phaseDuration = 1.0 / Double(phaseCount)
                let phaseIndex = min(Int(t / phaseDuration), phaseCount - 1)
                let phaseLocal = (t - Double(phaseIndex) * phaseDuration) / phaseDuration
                let eased = easeOut(phaseLocal)

                let phaseStart = phaseIndex == 0 ? 0 : phaseTargets[phaseIndex - 1]
                let phaseEnd = phaseTargets[phaseIndex]
                let interpolated = Double(phaseStart) + Double(phaseEnd - phaseStart) * eased

                let newPercent = Int(round(interpolated))
                if newPercent != displayedPercent {
                    displayedPercent = newPercent
                }
                progress = Double(newPercent) / 100.0

                // Advance the active step indicator when we cross into a new phase.
                if phaseIndex != currentStep {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        currentStep = phaseIndex
                    }
                    HapticManager.shared.gentle()
                }

                if t >= 1.0 {
                    timer.invalidate()
                    displayedPercent = 100
                    progress = 1.0
                    if currentStep != phaseCount - 1 {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentStep = phaseCount - 1
                        }
                    }

                    // Auto-advance once we hit 100% with a brief pause.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        guard !hasAdvanced else { return }
                        hasAdvanced = true
                        HapticManager.shared.success()
                        onContinue()
                    }
                }
            }
        }
    }

    /// Cubic ease-out — fast at start, slow at end. Makes each phase feel
    /// like the system is "thinking" then "settling".
    private func easeOut(_ t: Double) -> Double {
        let clamped = max(0, min(1, t))
        return 1 - pow(1 - clamped, 3)
    }
}

#Preview {
    PlanLoadingView(onContinue: {})
        .environment(\.theme, Theme())
}

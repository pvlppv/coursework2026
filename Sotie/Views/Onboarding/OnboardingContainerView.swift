//
//  OnboardingContainerView.swift
//  Sotie
//
//  Main onboarding shell with crossfade + slight vertical offset transitions.
//  Screens 1-13: Hook (1-5) + Survey (6-9) + Goals & Vision (11-13).
//

import SwiftUI

struct OnboardingContainerView: View {
    @Binding var isCompleted: Bool

    @State private var coordinator = OnboardingCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    /// We observe LanguageManager so a language switch from the in-onboarding
    /// picker triggers a body re-evaluation. Without this, calling
    /// `LanguageManager.shared.setLanguage(_:)` updates the storage but
    /// SwiftUI doesn't know to re-render the onboarding screens until the
    /// next step transition.
    @EnvironmentObject private var languageManager: LanguageManager

    /// Squeeze timer + discount paywall manager. Started on first appear,
    /// ended on completion / purchase / expiry. The same instance drives
    /// `shouldPresentDiscountPaywall`, which is flipped by:
    ///   - The deep link router (Live Activity tap).
    ///   - `OnboardingPaywallView` when the user dismisses the StoreKit
    ///     purchase sheet without buying.
    @StateObject private var discountActivity = OnboardingDiscountActivityManager.shared

    /// Tracks whether we've already logged abandonment for the current
    /// session, so multiple background transitions don't double-count.
    @State private var hasLoggedAbandonment = false

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            Group {
                switch coordinator.currentStep {
                case .welcome:
                    WelcomeView(onContinue: { coordinator.advance() })

                case .valueProp1:
                    ValuePropView(
                        config: .screen2(),
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .valueProp2:
                    ValuePropView(
                        config: .screen3(),
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .nameInput:
                    NameInputView(
                        userName: $coordinator.userName,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .considerThis:
                    ConsiderThisView(
                        name: coordinator.displayName,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .surveyThoughtType:
                    SurveyThoughtTypeView(
                        selection: $coordinator.thoughtType,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .surveyPattern:
                    SurveyPatternView(
                        selection: $coordinator.thoughtPattern,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .empathyCalculation:
                    EmpathyCalculationView(
                        name: coordinator.displayName,
                        targetHours: coordinator.empathyStats.hours,
                        days: coordinator.empathyStats.days,
                        verb: coordinator.empathyVerb,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .hopeScreen:
                    HopeScreenView(
                        name: coordinator.displayName,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .surveyGoals:
                    SurveyGoalsView(
                        selection: $coordinator.selectedGoals,
                        progress: OnboardingStep.surveyGoals.progressFraction,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .surveyVision:
                    SurveyVisionView(
                        selection: $coordinator.selectedVision,
                        progress: OnboardingStep.surveyVision.progressFraction,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .personalizedPlan:
                    PersonalizedPlanView(
                        goals: coordinator.orderedGoals,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .surveyFeeling:
                    SurveyFeelingView(
                        selection: $coordinator.thoughtFeeling,
                        progress: OnboardingStep.surveyFeeling.progressFraction,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .surveyBlocker:
                    SurveyBlockerView(
                        selection: $coordinator.thoughtBlocker,
                        progress: OnboardingStep.surveyBlocker.progressFraction,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .surveyUnderneath:
                    SurveyUnderneathView(
                        selection: $coordinator.thoughtUnderneath,
                        progress: OnboardingStep.surveyUnderneath.progressFraction,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .surveyHelp:
                    SurveyHelpView(
                        selection: $coordinator.thoughtHelp,
                        progress: OnboardingStep.surveyHelp.progressFraction,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .thankYou:
                    ThankYouView(
                        name: coordinator.displayName,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .surveySupportStyle:
                    SurveySupportStyleView(
                        selection: $coordinator.supportStyle,
                        progress: OnboardingStep.surveySupportStyle.progressFraction,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .surveySupportDepth:
                    SurveySupportDepthView(
                        selection: $coordinator.supportDepth,
                        progress: OnboardingStep.surveySupportDepth.progressFraction,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .journeySummary:
                    JourneySummaryView(
                        name: coordinator.displayName,
                        vision: coordinator.selectedVision,
                        feeling: coordinator.thoughtFeeling,
                        blocker: coordinator.thoughtBlocker,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .progressChart:
                    ProgressChartView(
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .demoConversation:
                    OnboardingConversationView(
                        name: coordinator.displayName,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .demoComplete:
                    DemoCompleteView(
                        onContinue: { coordinator.advance() }
                    )

                case .streakKickoff:
                    StreakKickoffView(
                        onContinue: { coordinator.advance() }
                    )

                case .planLoading:
                    PlanLoadingView(
                        onContinue: { coordinator.advance() }
                    )

                case .planReady:
                    PlanReadyView(
                        name: coordinator.displayName,
                        onContinue: { coordinator.advance() }
                    )

                case .clarityPlan:
                    ClarityPlanView(
                        name: coordinator.displayName,
                        targetDate: coordinator.clarityTargetDate,
                        onContinue: { coordinator.advance() }
                    )

                case .commitment:
                    CommitmentSurveyView(
                        selection: $coordinator.commitmentLevel,
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() }
                    )

                case .commitmentMessage:
                    CommitmentMessageView(
                        level: coordinator.commitmentLevel ?? .very,
                        onContinue: { coordinator.advance() }
                    )

                case .notificationsPriming:
                    NotificationsPrimingView(
                        onContinue: { coordinator.advance() }
                    )

                case .tryNowDemo:
                    TryNowDemoView(
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() },
                        onRestore: { restorePurchasesForOnboarding() }
                    )

                case .trialReminder:
                    TrialReminderView(
                        onBack: { coordinator.goBack() },
                        onContinue: { coordinator.advance() },
                        onRestore: { restorePurchasesForOnboarding() }
                    )

                case .onboardingPaywall:
                    OnboardingPaywallView(
                        onBack: { coordinator.goBack() },
                        onClose: { completeOnboarding() }
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 8)),
                removal: .opacity.combined(with: .offset(y: -8))
            ))
            // Combine step + language so a language switch forces the
            // current screen to re-render with new strings instead of
            // sticking with the stale ones until the next advance/back.
            .id("\(coordinator.currentStep.rawValue)-\(languageManager.currentLanguage.code)")

            // Language switcher: top-right, shown only on the very first
            // screens so users can correct an auto-detected language before
            // they invest time reading copy in the wrong one.
            if showsLanguageSwitcher {
                VStack {
                    HStack {
                        Spacer()
                        OnboardingLanguageSwitcher()
                            .padding(.trailing, Spacing.medium)
                            .padding(.top, Spacing.small)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            #if DEBUG
            VStack {
                Spacer()

                HStack {
                    Spacer()

                    Button {
                        completeOnboarding()
                    } label: {
                        Text("Debug: skip")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("debug.skipOnboarding")
                }
                .padding(.trailing, Spacing.medium)
                .padding(.bottom, Spacing.large)
            }
            #endif
        }
        .animation(.easeInOut(duration: 0.4), value: coordinator.currentStep)
        .onAppear {
            // Start the squeeze on first onboarding appearance. The manager
            // is idempotent: if a timer is already running (e.g. user
            // backgrounded mid-onboarding), this is a no-op.
            discountActivity.start()
        }
        .onOpenURL { url in
            // ContentView only forwards deep links once onboarding has
            // completed, so when the Live Activity is tapped during
            // onboarding the URL lands here. Reuse the same router.
            guard url.scheme == "sotiejournal" else { return }
            if url.host == "onboarding" {
                let path = url.pathComponents.filter { $0 != "/" }
                if path.first == "discount" {
                    discountActivity.requestPresentation()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // When the app goes to background or inactive while the user is
            // mid-onboarding, log the last visited step. This is our best
            // proxy for "user abandoned the funnel" — if they come back, we
            // simply log a fresh stepViewed on the resumed step.
            if newPhase == .background && !hasLoggedAbandonment {
                hasLoggedAbandonment = true
                Analytics.onboardingAbandoned(
                    lastStep: coordinator.currentStep.analyticsId,
                    lastStepIndex: coordinator.currentStep.rawValue
                )
            } else if newPhase == .active {
                hasLoggedAbandonment = false
            }
        }
    }

    /// Show the language picker on welcome + the two value-prop screens.
    /// After that the user has explicitly named themselves and is committed
    /// enough that the picker would just be visual noise.
    private var showsLanguageSwitcher: Bool {
        switch coordinator.currentStep {
        case .welcome, .valueProp1, .valueProp2:
            return true
        default:
            return false
        }
    }

    private func completeOnboarding() {
        HapticManager.shared.success()
        coordinator.markCompleted()
        // End the squeeze regardless of how onboarding ended (purchase or
        // skip). The manager picks the right reason via PremiumManager —
        // we use `.onboardingFinished` here as a safe default.
        discountActivity.end(reason: .onboardingFinished)
        withAnimation(.easeInOut(duration: 0.3)) {
            isCompleted = true
        }
    }

    /// Restore handler for screens before the paywall (TryNow / TrialReminder).
    /// Triggers a real App Store restore. If the user becomes premium as a
    /// result, the subscription-status observer in OnboardingPaywallView would
    /// also fire — but since we're upstream of the paywall, we call
    /// completeOnboarding directly here on success.
    private func restorePurchasesForOnboarding() {
        Task {
            try? await PremiumManager.shared.restorePurchases()
            await MainActor.run {
                if PremiumManager.shared.subscriptionStatus.isPremium {
                    completeOnboarding()
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var isCompleted = false
    OnboardingContainerView(isCompleted: $isCompleted)
        .environment(\.theme, Theme())
        .environmentObject(LanguageManager.shared)
}

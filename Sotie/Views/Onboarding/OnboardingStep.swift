//
//  OnboardingStep.swift
//  Sotie
//
//  Onboarding steps (screens 1-18).
//  Designed to extend cleanly as phases are added.
//

import Foundation

enum OnboardingStep: Int, CaseIterable, Equatable, Codable {
    case welcome = 0
    case valueProp1 = 1
    case valueProp2 = 2
    case nameInput = 3
    case considerThis = 4
    case surveyThoughtType = 5
    case surveyPattern = 6
    case empathyCalculation = 7
    case hopeScreen = 8
    // Phase 3: Goals & Vision (screens 11-13)
    case surveyGoals = 9
    case surveyVision = 10
    case personalizedPlan = 11
    // Phase 4: Deep dive (screens 14-18)
    case surveyFeeling = 12
    case surveyBlocker = 13
    case surveyUnderneath = 14
    case surveyHelp = 15
    case thankYou = 16
    // Phase 5: Support preferences & summary (screens 19-22)
    case surveySupportStyle = 17
    case surveySupportDepth = 18
    case journeySummary = 19
    case progressChart = 20
    // Phase 6: Demo conversation & completion (screens 23-24)
    case demoConversation = 21
    case demoComplete = 22
    // Phase 7: Streak kickoff + review prompt (screen 25)
    case streakKickoff = 23
    // Phase 8: Plan generation & commitment (screens 26-30)
    case planLoading = 24
    case planReady = 25
    case clarityPlan = 26
    case commitment = 27
    case commitmentMessage = 28
    // Phase 9: Notifications + demo + paywall (screens 31-34)
    case notificationsPriming = 29
    case tryNowDemo = 30
    case trialReminder = 31
    case onboardingPaywall = 32

    // MARK: - Navigation

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        guard rawValue > 0 else { return nil }
        return OnboardingStep(rawValue: rawValue - 1)
    }

    // MARK: - Screen Behavior

    /// Screens that show a visible back button (arrow in top-left).
    /// Text-only screens use invisible split-tap zones instead.
    var showsBackButton: Bool {
        switch self {
        case .nameInput, .surveyThoughtType, .surveyPattern,
             .surveyGoals, .surveyVision, .personalizedPlan,
             .surveyFeeling, .surveyBlocker, .surveyUnderneath, .surveyHelp,
             .surveySupportStyle, .surveySupportDepth, .journeySummary,
             .commitment, .tryNowDemo, .trialReminder:
            return true
        case .welcome, .valueProp1, .valueProp2, .considerThis,
             .empathyCalculation, .hopeScreen, .thankYou, .progressChart,
             .demoConversation, .demoComplete, .streakKickoff,
             .planLoading, .planReady, .clarityPlan, .commitmentMessage,
             .notificationsPriming, .onboardingPaywall:
            return false
        }
    }

    /// Screens that show the "tap to continue →" indicator at bottom.
    var showsTapToContinue: Bool {
        switch self {
        case .welcome, .valueProp1, .valueProp2, .considerThis,
             .empathyCalculation, .hopeScreen, .thankYou, .progressChart:
            return true
        case .nameInput, .surveyThoughtType, .surveyPattern,
             .surveyGoals, .surveyVision, .personalizedPlan,
             .surveyFeeling, .surveyBlocker, .surveyUnderneath, .surveyHelp,
             .surveySupportStyle, .surveySupportDepth, .journeySummary,
             .demoConversation, .demoComplete, .streakKickoff,
             .planLoading, .planReady, .clarityPlan, .commitment, .commitmentMessage,
             .notificationsPriming, .tryNowDemo, .trialReminder, .onboardingPaywall:
            return false
        }
    }

    // MARK: - Progress Bar

    /// Steps that show the progress bar.
    var showsProgressBar: Bool {
        switch self {
        case .surveyGoals, .surveyVision, .personalizedPlan,
             .surveyFeeling, .surveyBlocker, .surveyUnderneath, .surveyHelp,
             .surveySupportStyle, .surveySupportDepth:
            return true
        default:
            return false
        }
    }

    /// Progress fraction for the progress bar (0.0 to 1.0).
    var progressFraction: Double {
        switch self {
        case .surveyGoals: return 0.12
        case .surveyVision: return 0.24
        case .personalizedPlan: return 0.36
        case .surveyFeeling: return 0.45
        case .surveyBlocker: return 0.55
        case .surveyUnderneath: return 0.65
        case .surveyHelp: return 0.75
        case .surveySupportStyle: return 0.88
        case .surveySupportDepth: return 1.0
        default: return 0.0
        }
    }

    // MARK: - Analytics

    /// Stable string identifier sent to TelemetryDeck. We don't translate
    /// these because they're keys for funnel queries.
    var analyticsId: String {
        switch self {
        case .welcome: return "welcome"
        case .valueProp1: return "valueProp1"
        case .valueProp2: return "valueProp2"
        case .nameInput: return "nameInput"
        case .considerThis: return "considerThis"
        case .surveyThoughtType: return "surveyThoughtType"
        case .surveyPattern: return "surveyPattern"
        case .empathyCalculation: return "empathyCalculation"
        case .hopeScreen: return "hopeScreen"
        case .surveyGoals: return "surveyGoals"
        case .surveyVision: return "surveyVision"
        case .personalizedPlan: return "personalizedPlan"
        case .surveyFeeling: return "surveyFeeling"
        case .surveyBlocker: return "surveyBlocker"
        case .surveyUnderneath: return "surveyUnderneath"
        case .surveyHelp: return "surveyHelp"
        case .thankYou: return "thankYou"
        case .surveySupportStyle: return "surveySupportStyle"
        case .surveySupportDepth: return "surveySupportDepth"
        case .journeySummary: return "journeySummary"
        case .progressChart: return "progressChart"
        case .demoConversation: return "demoConversation"
        case .demoComplete: return "demoComplete"
        case .streakKickoff: return "streakKickoff"
        case .planLoading: return "planLoading"
        case .planReady: return "planReady"
        case .clarityPlan: return "clarityPlan"
        case .commitment: return "commitment"
        case .commitmentMessage: return "commitmentMessage"
        case .notificationsPriming: return "notificationsPriming"
        case .tryNowDemo: return "tryNowDemo"
        case .trialReminder: return "trialReminder"
        case .onboardingPaywall: return "onboardingPaywall"
        }
    }
}

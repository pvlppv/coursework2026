//
//  SurveyModels.swift
//  Sotie
//
//  Data models for the onboarding survey.
//  Screen 6: thought type. Screen 7: combined frequency + duration pattern.
//  Screen 11: goals. Screen 12: deeper vision.
//

import Foundation

// MARK: - Screen 6: "what kind of thought keeps coming back?"

enum ThoughtType: String, CaseIterable, Identifiable {
    case someone
    case whatHappened
    case somethingIDid
    case whatToDo
    case feeling
    case myself

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .someone: return "🧑"
        case .whatHappened: return "💫"
        case .somethingIDid: return "😶"
        case .whatToDo: return "🤔"
        case .feeling: return "🫠"
        case .myself: return "🪞"
        }
    }

    var localizedTitle: String {
        switch self {
        case .someone:
            return appLocalizedString(Localizable.onboardingFlowSurveyThoughtSomeone)
        case .whatHappened:
            return appLocalizedString(Localizable.onboardingFlowSurveyThoughtWhatHappened)
        case .somethingIDid:
            return appLocalizedString(Localizable.onboardingFlowSurveyThoughtSomethingIDid)
        case .whatToDo:
            return appLocalizedString(Localizable.onboardingFlowSurveyThoughtWhatToDo)
        case .feeling:
            return appLocalizedString(Localizable.onboardingFlowSurveyThoughtFeeling)
        case .myself:
            return appLocalizedString(Localizable.onboardingFlowSurveyThoughtMyself)
        }
    }
}

// MARK: - Screen 7: Combined frequency + duration
// "how often does it come back?" — each option encodes both frequency and duration.

enum ThoughtPattern: String, CaseIterable, Identifiable {
    case allTheTime       // "all the time and stays forever"
    case prettyOften      // "pretty often and stays hours"
    case sometimes        // "sometimes and keeps coming back"
    case notMuch          // "not much and stays a while"
    case rarely           // "rarely and stays not long"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .allTheTime: return "🔁"
        case .prettyOften: return "🌊"
        case .sometimes: return "💭"
        case .notMuch: return "🍃"
        case .rarely: return "🌫️"
        }
    }

    var localizedTitle: String {
        switch self {
        case .allTheTime:
            return appLocalizedString(Localizable.onboardingFlowSurveyPatternAllTheTime)
        case .prettyOften:
            return appLocalizedString(Localizable.onboardingFlowSurveyPatternPrettyOften)
        case .sometimes:
            return appLocalizedString(Localizable.onboardingFlowSurveyPatternSometimes)
        case .notMuch:
            return appLocalizedString(Localizable.onboardingFlowSurveyPatternNotMuch)
        case .rarely:
            return appLocalizedString(Localizable.onboardingFlowSurveyPatternRarely)
        }
    }

    /// Episodes per day (for empathy calculation)
    var episodesPerDay: Double {
        switch self {
        case .allTheTime: return 8.0
        case .prettyOften: return 5.0
        case .sometimes: return 3.0
        case .notMuch: return 1.5
        case .rarely: return 0.5
        }
    }

    /// Hours per episode (for empathy calculation)
    var hoursPerEpisode: Double {
        switch self {
        case .allTheTime: return 3.0
        case .prettyOften: return 2.0
        case .sometimes: return 1.5
        case .notMuch: return 1.0
        case .rarely: return 0.5
        }
    }
}


// MARK: - Screen 11: "what do you want to achieve with sotie?"

enum OnboardingGoal: String, CaseIterable, Identifiable {
    case feelClearer
    case stopReplayingThings
    case understandMyFeelings
    case knowWhatToDoNext
    case sleepWithQuieterMind
    case feelLessAloneWithIt
    case spotMyPatterns

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .feelClearer: return "🔍"
        case .stopReplayingThings: return "🔁"
        case .understandMyFeelings: return "🫶"
        case .knowWhatToDoNext: return "✨"
        case .sleepWithQuieterMind: return "🌙"
        case .feelLessAloneWithIt: return "🫂"
        case .spotMyPatterns: return "👀"
        }
    }

    var localizedTitle: String {
        switch self {
        case .feelClearer:
            return appLocalizedString(Localizable.onboardingFlowGoalFeelClearer)
        case .stopReplayingThings:
            return appLocalizedString(Localizable.onboardingFlowGoalStopReplaying)
        case .understandMyFeelings:
            return appLocalizedString(Localizable.onboardingFlowGoalUnderstandFeelings)
        case .knowWhatToDoNext:
            return appLocalizedString(Localizable.onboardingFlowGoalKnowWhatToDo)
        case .sleepWithQuieterMind:
            return appLocalizedString(Localizable.onboardingFlowGoalSleepQuieter)
        case .feelLessAloneWithIt:
            return appLocalizedString(Localizable.onboardingFlowGoalFeelLessAlone)
        case .spotMyPatterns:
            return appLocalizedString(Localizable.onboardingFlowGoalSpotPatterns)
        }
    }

    /// Description shown on the personalized plan screen (screen 13).
    var localizedDescription: String {
        switch self {
        case .feelClearer:
            return appLocalizedString(Localizable.onboardingFlowGoalDescFeelClearer)
        case .stopReplayingThings:
            return appLocalizedString(Localizable.onboardingFlowGoalDescStopReplaying)
        case .understandMyFeelings:
            return appLocalizedString(Localizable.onboardingFlowGoalDescUnderstandFeelings)
        case .knowWhatToDoNext:
            return appLocalizedString(Localizable.onboardingFlowGoalDescKnowWhatToDo)
        case .sleepWithQuieterMind:
            return appLocalizedString(Localizable.onboardingFlowGoalDescSleepQuieter)
        case .feelLessAloneWithIt:
            return appLocalizedString(Localizable.onboardingFlowGoalDescFeelLessAlone)
        case .spotMyPatterns:
            return appLocalizedString(Localizable.onboardingFlowGoalDescSpotPatterns)
        }
    }

    /// Maps to the existing AIReflectionPrimaryGoal for settings persistence.
    var aiGoal: AIReflectionPrimaryGoal {
        switch self {
        case .feelClearer: return .feelClearer
        case .stopReplayingThings: return .stopReplayingThings
        case .understandMyFeelings: return .understandMyFeelings
        case .knowWhatToDoNext: return .knowWhatToDoNext
        case .sleepWithQuieterMind: return .sleepWithQuieterMind
        case .feelLessAloneWithIt: return .feelLessAloneWithIt
        case .spotMyPatterns: return .spotMyPatterns
        }
    }
}

// MARK: - Screen 12: "thinking bigger, what would a clearer mind look like for you?"

enum OnboardingVision: String, CaseIterable, Identifiable {
    case trustingMyselfMore
    case namingWhatIFeel
    case comingBackToMyself
    case replyingFromClarity
    case sleepingWithoutOverthinking
    case stayingInControl

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .trustingMyselfMore: return "🫰"
        case .namingWhatIFeel: return "🫶"
        case .comingBackToMyself: return "🤗"
        case .replyingFromClarity: return "😌"
        case .sleepingWithoutOverthinking: return "🌙"
        case .stayingInControl: return "🧘"
        }
    }

    var localizedTitle: String {
        switch self {
        case .trustingMyselfMore:
            return appLocalizedString(Localizable.onboardingFlowVisionTrusting)
        case .namingWhatIFeel:
            return appLocalizedString(Localizable.onboardingFlowVisionNaming)
        case .comingBackToMyself:
            return appLocalizedString(Localizable.onboardingFlowVisionComingBack)
        case .replyingFromClarity:
            return appLocalizedString(Localizable.onboardingFlowVisionReplying)
        case .sleepingWithoutOverthinking:
            return appLocalizedString(Localizable.onboardingFlowVisionSleeping)
        case .stayingInControl:
            return appLocalizedString(Localizable.onboardingFlowVisionStaying)
        }
    }
}

// MARK: - Screen 14: "how does this thought feel right now?"

enum ThoughtFeeling: String, CaseIterable, Identifiable {
    case keepsLooping
    case feelsUnresolved
    case hardToExplain
    case stillHurts
    case feelsMessy
    case getsLoudAtNight

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .keepsLooping: return "🔄"
        case .feelsUnresolved: return "😔"
        case .hardToExplain: return "💬"
        case .stillHurts: return "❤️"
        case .feelsMessy: return "🫠"
        case .getsLoudAtNight: return "🌙"
        }
    }

    var localizedTitle: String {
        switch self {
        case .keepsLooping:
            return appLocalizedString(Localizable.onboardingFlowFeelingKeepsLooping)
        case .feelsUnresolved:
            return appLocalizedString(Localizable.onboardingFlowFeelingUnresolved)
        case .hardToExplain:
            return appLocalizedString(Localizable.onboardingFlowFeelingHardToExplain)
        case .stillHurts:
            return appLocalizedString(Localizable.onboardingFlowFeelingStillHurts)
        case .feelsMessy:
            return appLocalizedString(Localizable.onboardingFlowFeelingMessy)
        case .getsLoudAtNight:
            return appLocalizedString(Localizable.onboardingFlowFeelingLoudAtNight)
        }
    }
}

// MARK: - Screen 15: "what's the main thing that gets in the way?"

enum ThoughtBlocker: String, CaseIterable, Identifiable {
    case noClearAnswer
    case thingsLeftUnsaid
    case tooManyWhatIfs
    case tryingToSolveItAlone
    case rereadingEverything
    case waitingForItToPass

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .noClearAnswer: return "😶"
        case .thingsLeftUnsaid: return "🤐"
        case .tooManyWhatIfs: return "💭"
        case .tryingToSolveItAlone: return "🧍"
        case .rereadingEverything: return "📱"
        case .waitingForItToPass: return "⏳"
        }
    }

    var localizedTitle: String {
        switch self {
        case .noClearAnswer:
            return appLocalizedString(Localizable.onboardingFlowBlockerNoClearAnswer)
        case .thingsLeftUnsaid:
            return appLocalizedString(Localizable.onboardingFlowBlockerThingsUnsaid)
        case .tooManyWhatIfs:
            return appLocalizedString(Localizable.onboardingFlowBlockerWhatIfs)
        case .tryingToSolveItAlone:
            return appLocalizedString(Localizable.onboardingFlowBlockerSolveAlone)
        case .rereadingEverything:
            return appLocalizedString(Localizable.onboardingFlowBlockerRereading)
        case .waitingForItToPass:
            return appLocalizedString(Localizable.onboardingFlowBlockerWaiting)
        }
    }
}

// MARK: - Screen 16: "what do you think is underneath it?"

enum ThoughtUnderneath: String, CaseIterable, Identifiable {
    case needingReassurance
    case needingClosure
    case wantingToBeHeard
    case doubtingMyself
    case feelingHurt
    case wantingItToMakeSense

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .needingReassurance: return "🫂"
        case .needingClosure: return "🚪"
        case .wantingToBeHeard: return "👂"
        case .doubtingMyself: return "😟"
        case .feelingHurt: return "❤️"
        case .wantingItToMakeSense: return "🧩"
        }
    }

    var localizedTitle: String {
        switch self {
        case .needingReassurance:
            return appLocalizedString(Localizable.onboardingFlowUnderneathReassurance)
        case .needingClosure:
            return appLocalizedString(Localizable.onboardingFlowUnderneathClosure)
        case .wantingToBeHeard:
            return appLocalizedString(Localizable.onboardingFlowUnderneathHeard)
        case .doubtingMyself:
            return appLocalizedString(Localizable.onboardingFlowUnderneathDoubting)
        case .feelingHurt:
            return appLocalizedString(Localizable.onboardingFlowUnderneathHurt)
        case .wantingItToMakeSense:
            return appLocalizedString(Localizable.onboardingFlowUnderneathMakeSense)
        }
    }
}

// MARK: - Screen 17: "what would help right now?"

enum ThoughtHelp: String, CaseIterable, Identifiable {
    case understandIt
    case putItIntoWords
    case slowItDown
    case seeItClearly
    case knowWhatToDo
    case leaveItForTonight

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .understandIt: return "🫶"
        case .putItIntoWords: return "📝"
        case .slowItDown: return "🐌"
        case .seeItClearly: return "👁️"
        case .knowWhatToDo: return "✨"
        case .leaveItForTonight: return "🌙"
        }
    }

    var localizedTitle: String {
        switch self {
        case .understandIt:
            return appLocalizedString(Localizable.onboardingFlowHelpUnderstand)
        case .putItIntoWords:
            return appLocalizedString(Localizable.onboardingFlowHelpPutIntoWords)
        case .slowItDown:
            return appLocalizedString(Localizable.onboardingFlowHelpSlowDown)
        case .seeItClearly:
            return appLocalizedString(Localizable.onboardingFlowHelpSeeClearly)
        case .knowWhatToDo:
            return appLocalizedString(Localizable.onboardingFlowHelpKnowWhatToDo)
        case .leaveItForTonight:
            return appLocalizedString(Localizable.onboardingFlowHelpLeaveTonight)
        }
    }
}

// MARK: - Commitment level (Screen 29 — final commitment ask)

enum CommitmentLevel: String, CaseIterable, Identifiable {
    case extremely
    case very
    case somewhat
    case aLittle
    case justTrying

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .extremely: return "🔥"
        case .very: return "🌿"
        case .somewhat: return "🌗"
        case .aLittle: return "🌱"
        case .justTrying: return "🪶"
        }
    }

    var localizedTitle: String {
        switch self {
        case .extremely:
            return appLocalizedString(Localizable.onboardingFlowCommitmentExtremely)
        case .very:
            return appLocalizedString(Localizable.onboardingFlowCommitmentVery)
        case .somewhat:
            return appLocalizedString(Localizable.onboardingFlowCommitmentSomewhat)
        case .aLittle:
            return appLocalizedString(Localizable.onboardingFlowCommitmentLittle)
        case .justTrying:
            return appLocalizedString(Localizable.onboardingFlowCommitmentJustTrying)
        }
    }

    /// Headline used on the final commitment-message screen.
    var localizedMessageTitle: String {
        switch self {
        case .extremely:
            return appLocalizedString(Localizable.onboardingFlowCommitmentMsgExtremelyTitle)
        case .very:
            return appLocalizedString(Localizable.onboardingFlowCommitmentMsgVeryTitle)
        case .somewhat:
            return appLocalizedString(Localizable.onboardingFlowCommitmentMsgSomewhatTitle)
        case .aLittle:
            return appLocalizedString(Localizable.onboardingFlowCommitmentMsgLittleTitle)
        case .justTrying:
            return appLocalizedString(Localizable.onboardingFlowCommitmentMsgJustTryingTitle)
        }
    }

    /// Body text for the final commitment-message screen.
    var localizedMessageBody: String {
        switch self {
        case .extremely:
            return appLocalizedString(Localizable.onboardingFlowCommitmentMsgExtremelyBody)
        case .very:
            return appLocalizedString(Localizable.onboardingFlowCommitmentMsgVeryBody)
        case .somewhat:
            return appLocalizedString(Localizable.onboardingFlowCommitmentMsgSomewhatBody)
        case .aLittle:
            return appLocalizedString(Localizable.onboardingFlowCommitmentMsgLittleBody)
        case .justTrying:
            return appLocalizedString(Localizable.onboardingFlowCommitmentMsgJustTryingBody)
        }
    }
}

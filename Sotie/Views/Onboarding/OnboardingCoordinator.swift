//
//  OnboardingCoordinator.swift
//  Sotie
//
//  Observable state machine for the onboarding flow.
//  Handles step navigation, persistence (resume on relaunch),
//  and user data collection.
//

import SwiftUI
import Observation

@Observable
final class OnboardingCoordinator {

    // MARK: - State

    var currentStep: OnboardingStep
    var userName: String = ""

    // Survey answers
    var thoughtType: ThoughtType?
    var thoughtPattern: ThoughtPattern?
    var selectedGoals: Set<OnboardingGoal> = []
    var selectedVision: OnboardingVision?
    // Phase 4
    var thoughtFeeling: ThoughtFeeling?
    var thoughtBlocker: ThoughtBlocker?
    var thoughtUnderneath: ThoughtUnderneath?
    var thoughtHelp: ThoughtHelp?
    // Phase 5
    var supportStyle: AIReflectionSupportStyle?
    var supportDepth: AIReflectionSupportDepth?
    // Phase 8
    var commitmentLevel: CommitmentLevel?

    // MARK: - Persistence Keys

    private static let lastStepKey = "onboardingLastStep"
    private static let userNameKey = "onboardingUserName"
    private static let thoughtTypeKey = "onboardingSurveyThoughtType"
    private static let patternKey = "onboardingSurveyPattern"
    private static let goalsKey = "onboardingSurveyGoals"
    private static let visionKey = "onboardingSurveyVision"
    private static let feelingKey = "onboardingSurveyFeeling"
    private static let blockerKey = "onboardingSurveyBlocker"
    private static let underneathKey = "onboardingSurveyUnderneath"
    private static let helpKey = "onboardingSurveyHelp"
    private static let styleKey = "onboardingSurveyStyle"
    private static let depthKey = "onboardingSurveyDepth"
    private static let commitmentKey = "onboardingCommitmentLevel"

    // MARK: - Init (resume from last saved step)

    init() {
        let savedStep = UserDefaults.standard.integer(forKey: Self.lastStepKey)
        self.currentStep = OnboardingStep(rawValue: savedStep) ?? .welcome
        self.userName = UserDefaults.standard.string(forKey: Self.userNameKey) ?? ""

        // Restore survey answers
        if let rawThought = UserDefaults.standard.string(forKey: Self.thoughtTypeKey) {
            self.thoughtType = ThoughtType(rawValue: rawThought)
        }
        if let rawPattern = UserDefaults.standard.string(forKey: Self.patternKey) {
            self.thoughtPattern = ThoughtPattern(rawValue: rawPattern)
        }
        if let rawGoals = UserDefaults.standard.stringArray(forKey: Self.goalsKey) {
            self.selectedGoals = Set(rawGoals.compactMap { OnboardingGoal(rawValue: $0) })
        }
        if let rawVision = UserDefaults.standard.string(forKey: Self.visionKey) {
            self.selectedVision = OnboardingVision(rawValue: rawVision)
        }
        if let rawFeeling = UserDefaults.standard.string(forKey: Self.feelingKey) {
            self.thoughtFeeling = ThoughtFeeling(rawValue: rawFeeling)
        }
        if let rawBlocker = UserDefaults.standard.string(forKey: Self.blockerKey) {
            self.thoughtBlocker = ThoughtBlocker(rawValue: rawBlocker)
        }
        if let rawUnderneath = UserDefaults.standard.string(forKey: Self.underneathKey) {
            self.thoughtUnderneath = ThoughtUnderneath(rawValue: rawUnderneath)
        }
        if let rawHelp = UserDefaults.standard.string(forKey: Self.helpKey) {
            self.thoughtHelp = ThoughtHelp(rawValue: rawHelp)
        }
        if let rawStyle = UserDefaults.standard.string(forKey: Self.styleKey) {
            self.supportStyle = AIReflectionSupportStyle(rawValue: rawStyle)
        }
        if let rawDepth = UserDefaults.standard.string(forKey: Self.depthKey) {
            self.supportDepth = AIReflectionSupportDepth(rawValue: rawDepth)
        }
        if let rawCommitment = UserDefaults.standard.string(forKey: Self.commitmentKey) {
            self.commitmentLevel = CommitmentLevel(rawValue: rawCommitment)
        }

        // Funnel: log the initial step the user lands on (whether it's
        // welcome on a fresh install or a resumed step on relaunch).
        Analytics.onboardingStepViewed(
            step: currentStep.analyticsId,
            index: currentStep.rawValue
        )
    }

    // MARK: - Navigation

    func advance() {
        guard let next = currentStep.next else { return }
        let from = currentStep
        persistAll()
        // Save AI reflection settings before demo so the engine uses them
        if next == .demoConversation {
            persistAIReflectionSettings()
        }
        currentStep = next
        persist()
        HapticManager.shared.light()
        Analytics.onboardingStepAdvanced(from: from.analyticsId, to: next.analyticsId)
        Analytics.onboardingStepViewed(step: next.analyticsId, index: next.rawValue)
    }

    func goBack() {
        guard let previous = currentStep.previous else { return }
        let from = currentStep
        currentStep = previous
        persist()
        HapticManager.shared.soft()
        Analytics.onboardingStepBacked(from: from.analyticsId, to: previous.analyticsId)
        Analytics.onboardingStepViewed(step: previous.analyticsId, index: previous.rawValue)
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(currentStep.rawValue, forKey: Self.lastStepKey)
    }

    private func persistAll() {
        persistUserName()
        persistSurvey()
    }

    private func persistUserName() {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: Self.userNameKey)
        }
    }

    private func persistSurvey() {
        if let t = thoughtType {
            UserDefaults.standard.set(t.rawValue, forKey: Self.thoughtTypeKey)
        }
        if let p = thoughtPattern {
            UserDefaults.standard.set(p.rawValue, forKey: Self.patternKey)
        }
        if !selectedGoals.isEmpty {
            UserDefaults.standard.set(selectedGoals.map(\.rawValue), forKey: Self.goalsKey)
        }
        if let v = selectedVision {
            UserDefaults.standard.set(v.rawValue, forKey: Self.visionKey)
        }
        if let f = thoughtFeeling {
            UserDefaults.standard.set(f.rawValue, forKey: Self.feelingKey)
        }
        if let b = thoughtBlocker {
            UserDefaults.standard.set(b.rawValue, forKey: Self.blockerKey)
        }
        if let u = thoughtUnderneath {
            UserDefaults.standard.set(u.rawValue, forKey: Self.underneathKey)
        }
        if let h = thoughtHelp {
            UserDefaults.standard.set(h.rawValue, forKey: Self.helpKey)
        }
        if let s = supportStyle {
            UserDefaults.standard.set(s.rawValue, forKey: Self.styleKey)
        }
        if let d = supportDepth {
            UserDefaults.standard.set(d.rawValue, forKey: Self.depthKey)
        }
        if let c = commitmentLevel {
            UserDefaults.standard.set(c.rawValue, forKey: Self.commitmentKey)
        }
    }

    /// Call when onboarding completes to clean up intermediate state.
    func markCompleted() {
        persistAll()
        persistAIReflectionSettings()
        UserDefaults.standard.removeObject(forKey: Self.lastStepKey)
    }

    /// Saves the collected support style, depth, and goals to AIReflectionSettingsStore
    /// so the AI engine uses them immediately (including during the onboarding demo).
    private func persistAIReflectionSettings() {
        var settings = AIReflectionSettingsStore.load()
        if let style = supportStyle {
            settings.supportStyle = style
        }
        if let depth = supportDepth {
            settings.supportDepth = depth
        }
        if !selectedGoals.isEmpty {
            settings.primaryGoals = orderedGoals.map(\.aiGoal)
        }
        AIReflectionSettingsStore.save(settings)
    }

    /// Display name with fallback.
    var displayName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appLocalizedString(Localizable.onboardingFlowNameFallback) : trimmed
    }

    // MARK: - Empathy Calculation

    /// Computes the "hours per year" stat based on the combined pattern selection.
    var empathyStats: (hours: Int, days: Int) {
        let pattern = thoughtPattern ?? .sometimes

        let hoursPerYear = Int(pattern.episodesPerDay * pattern.hoursPerEpisode * 365)
        let days = hoursPerYear / 24
        return (hours: hoursPerYear, days: days)
    }

    /// The empathy screen verb depends on thought type selection.
    var empathyVerb: String {
        guard let type = thoughtType else {
            return appLocalizedString(Localizable.onboardingFlowEmpathyVerbDefault)
        }
        return switch type {
        case .someone:
            appLocalizedString(Localizable.onboardingFlowEmpathyVerbSomeone)
        case .whatHappened:
            appLocalizedString(Localizable.onboardingFlowEmpathyVerbWhatHappened)
        case .somethingIDid:
            appLocalizedString(Localizable.onboardingFlowEmpathyVerbSomethingIDid)
        case .whatToDo:
            appLocalizedString(Localizable.onboardingFlowEmpathyVerbWhatToDo)
        case .feeling:
            appLocalizedString(Localizable.onboardingFlowEmpathyVerbFeeling)
        case .myself:
            appLocalizedString(Localizable.onboardingFlowEmpathyVerbMyself)
        }
    }

    // MARK: - Goals (Screen 13)

    /// Goals in their original enum order for consistent display on the plan screen.
    var orderedGoals: [OnboardingGoal] {
        OnboardingGoal.allCases.filter { selectedGoals.contains($0) }
    }

    // MARK: - Plan target date

    /// Date used on the clarity plan screen ("you'll have a clearer mind by ...").
    /// Always one week from the moment the user reaches the plan screen.
    /// Computed lazily so the date is fresh whenever the screen appears.
    var clarityTargetDate: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(7 * 86400)
    }
}

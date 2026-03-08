import Foundation

enum AIReflectionSupportStyle: String, CaseIterable, Identifiable, Sendable {
  case gentle
  case warm
  case calming
  case clear
  case practical
  case softButDirect = "soft_but_direct"

  nonisolated var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .gentle: return Localizable.aiSettingsStyleGentle
    case .warm: return Localizable.aiSettingsStyleWarm
    case .calming: return Localizable.aiSettingsStyleCalming
    case .clear: return Localizable.aiSettingsStyleClear
    case .practical: return Localizable.aiSettingsStylePractical
    case .softButDirect: return Localizable.aiSettingsStyleSoftButDirect
    }
  }
}

enum AIReflectionSupportDepth: String, CaseIterable, Identifiable, Sendable {
  case calmMeFirst = "calm_me_first"
  case helpMeUnderstandIt = "help_me_understand_it"
  case askWhatMatters = "ask_what_matters"
  case showMeThePattern = "show_me_the_pattern"
  case helpMeSeeItDifferently = "help_me_see_it_differently"
  case giveMeNextSteps = "give_me_next_steps"

  nonisolated var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .calmMeFirst: return Localizable.aiSettingsDepthCalmMeFirst
    case .helpMeUnderstandIt: return Localizable.aiSettingsDepthHelpMeUnderstandIt
    case .askWhatMatters: return Localizable.aiSettingsDepthAskWhatMatters
    case .showMeThePattern: return Localizable.aiSettingsDepthShowMeThePattern
    case .helpMeSeeItDifferently: return Localizable.aiSettingsDepthHelpMeSeeItDifferently
    case .giveMeNextSteps: return Localizable.aiSettingsDepthGiveMeNextSteps
    }
  }
}

enum AIReflectionPrimaryGoal: String, CaseIterable, Identifiable, Sendable {
  case feelClearer = "feel_clearer"
  case stopReplayingThings = "stop_replaying_things"
  case understandMyFeelings = "understand_my_feelings"
  case knowWhatToDoNext = "know_what_to_do_next"
  case sleepWithQuieterMind = "sleep_with_quieter_mind"
  case feelLessAloneWithIt = "feel_less_alone_with_it"
  case spotMyPatterns = "spot_my_patterns"

  nonisolated var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .feelClearer: return Localizable.aiSettingsGoalFeelClearer
    case .stopReplayingThings: return Localizable.aiSettingsGoalStopReplayingThings
    case .understandMyFeelings: return Localizable.aiSettingsGoalUnderstandMyFeelings
    case .knowWhatToDoNext: return Localizable.aiSettingsGoalKnowWhatToDoNext
    case .sleepWithQuieterMind: return Localizable.aiSettingsGoalSleepWithQuieterMind
    case .feelLessAloneWithIt: return Localizable.aiSettingsGoalFeelLessAloneWithIt
    case .spotMyPatterns: return Localizable.aiSettingsGoalSpotMyPatterns
    }
  }
}

struct AIReflectionSettings: Equatable, Sendable {
  var supportStyle: AIReflectionSupportStyle
  var supportDepth: AIReflectionSupportDepth
  var primaryGoals: [AIReflectionPrimaryGoal]

  nonisolated static let defaults = AIReflectionSettings(
    supportStyle: .softButDirect,
    supportDepth: .showMeThePattern,
    primaryGoals: [.feelClearer, .stopReplayingThings, .spotMyPatterns]
  )

  nonisolated var promptJSONObject: [String: Any] {
    [
      "support_style": supportStyle.rawValue,
      "support_depth": supportDepth.rawValue,
      "primary_goals": primaryGoals.map(\.rawValue),
    ]
  }

  nonisolated var promptJSON: String {
    let payload = ["user_settings": promptJSONObject]

    guard JSONSerialization.isValidJSONObject(payload),
      let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    else {
      return """
        {"user_settings":{"primary_goals":["feel_clearer","stop_replaying_things","spot_my_patterns"],"support_depth":"show_me_the_pattern","support_style":"soft_but_direct"}}
        """
    }

    return json
  }
}

enum AIReflectionSettingsStore {
  nonisolated static let storageKey = "AIReflectionSettings.v1"
  nonisolated private static let supportStyleKey = "\(storageKey).supportStyle"
  nonisolated private static let supportDepthKey = "\(storageKey).supportDepth"
  nonisolated private static let primaryGoalsKey = "\(storageKey).primaryGoals"

  nonisolated static func load(from defaults: UserDefaults = .standard) -> AIReflectionSettings {
    let fallback = AIReflectionSettings.defaults
    let style = defaults.string(forKey: supportStyleKey)
      .flatMap(AIReflectionSupportStyle.init(rawValue:)) ?? fallback.supportStyle
    let depth = defaults.string(forKey: supportDepthKey)
      .flatMap(AIReflectionSupportDepth.init(rawValue:)) ?? fallback.supportDepth
    let goals = (defaults.stringArray(forKey: primaryGoalsKey) ?? [])
      .compactMap(AIReflectionPrimaryGoal.init(rawValue:))

    return AIReflectionSettings(
      supportStyle: style,
      supportDepth: depth,
      primaryGoals: goals.isEmpty ? fallback.primaryGoals : goals
    )
  }

  nonisolated static func save(_ settings: AIReflectionSettings, to defaults: UserDefaults = .standard) {
    defaults.set(settings.supportStyle.rawValue, forKey: supportStyleKey)
    defaults.set(settings.supportDepth.rawValue, forKey: supportDepthKey)
    defaults.set(settings.primaryGoals.map(\.rawValue), forKey: primaryGoalsKey)
  }

  nonisolated static func reset(in defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: storageKey)
    defaults.removeObject(forKey: supportStyleKey)
    defaults.removeObject(forKey: supportDepthKey)
    defaults.removeObject(forKey: primaryGoalsKey)
  }
}

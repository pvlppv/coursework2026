//
//  PromptCluster.swift
//  Sotie
//
//
//  User-visible surface for the prompt rail above the AddEntry textarea.
//
//  Each cluster groups one or more `PromptCategory` sub-states. The user
//  picks a cluster on the rail (single tap → opener fires); the picker
//  draws an opener at random from the union of the cluster's sub-state
//  pools, and the resulting `subState` drives the icon variety on the
//  selected cluster card. Sub-states themselves are never shown to the user.
//

import Foundation

/// User-visible cluster shown on the AddEntry prompt rail.
///
/// Order of cases matches the cold-start rail layout: time first (when
/// applicable), brain dump last, the rest sorted by typical importance.
enum PromptCluster: String, CaseIterable, Codable, Sendable, Hashable {
  case time
  case heavy
  case looping
  case someone
  case choosing
  case notice
  case brainDump = "brain_dump"

  /// Stable identifier used for analytics + persistence.
  var id: String { rawValue }

  /// Sub-states absorbed into this cluster. The opener picker unions these
  /// pools when drawing for non-time clusters; the time cluster is special-
  /// cased by hour at runtime.
  var subStates: [PromptCategory] {
    switch self {
    case .time: return [.morning, .evening, .lateNight]
    case .heavy: return [.heavy, .numb, .anxious, .frustrated]
    case .looping: return [.stuck, .replay, .restless]
    case .someone: return [.someone, .youVsThem]
    case .choosing: return [.decision, .change]
    case .notice: return [.wins, .gratitude, .patterns, .futureSelf]
    case .brainDump: return [.brainDump]
    }
  }

  /// Whether this cluster appears in the regular engagement-weighted slot
  /// pool. Time and Brain dump are positioned by fixed rules, not by score.
  var isInRegularRotation: Bool {
    switch self {
    case .time, .brainDump: return false
    default: return true
    }
  }

  /// Localized title key for non-time clusters. The time cluster resolves
  /// its title via `timeTitleKey(forHour:)` instead.
  var titleKey: String {
    switch self {
    case .time: return "prompts.cluster.time.title.morning"  // unused; caller routes via timeTitleKey
    default: return "prompts.cluster.\(rawValue).title"
    }
  }

  /// Localized subtitle key for non-time clusters.
  /// Deprecated — subtitles were removed from the card UI; the keys are
  /// kept on `PromptCluster` only for back-compat with any tooling that
  /// still references them. Cards no longer render subtitles.
  var subtitleKey: String {
    switch self {
    case .time: return "prompts.cluster.time.subtitle.morning"  // unused
    default: return "prompts.cluster.\(rawValue).subtitle"
    }
  }

  /// Asset catalog name for the default illustration shown before any
  /// opener is picked. The selected card swaps to the picked sub-state's
  /// illustration via `selectedSubStateImageOverride`.
  var defaultIllustration: String {
    switch self {
    case .time: return "prompt_morning"  // overridden at runtime by hour
    case .heavy: return "prompt_heavy"
    case .looping: return "prompt_stuck"
    case .someone: return "prompt_someone"
    case .choosing: return "prompt_decision"
    case .notice: return "prompt_wins"
    case .brainDump: return "prompt_brain_dump"
    }
  }

  /// Short, directional line shown to the AI as "where the user came from".
  /// Deliberately not instructional — the system prompt decides what to do
  /// with it. Time-cluster callers should use `timeAiLensHint(forHour:)`.
  var aiLensHint: String {
    switch self {
    case .time:
      // Caller must use `timeAiLensHint(forHour:)`; this is a safe fallback.
      return "Direction: time-of-day."
    case .heavy:
      return "Direction: heaviness, sadness, numbness, anxiety, or frustration."
    case .looping:
      return "Direction: a thought that keeps coming back."
    case .someone:
      return "Direction: another person on the user's mind."
    case .choosing:
      return "Direction: a fork or transition."
    case .notice:
      return "Direction: noticing what is good or what repeats."
    case .brainDump:
      return "Direction: open dump, no fixed topic."
    }
  }

  // MARK: - Time-cluster runtime helpers

  /// Returns the time cluster only if the hour falls in one of the time
  /// windows (5-11 morning, 18-22 evening, 23 or 0-4 late night). Otherwise
  /// returns nil — the rail then fills slot 1 from regular rotation.
  static func currentTimeCluster(forHour hour: Int) -> PromptCluster? {
    guard timeSubState(forHour: hour) != nil else { return nil }
    return .time
  }

  /// Resolves the time-cluster sub-state for a given hour, or nil when the
  /// hour falls into the midday gap (12-17).
  static func timeSubState(forHour hour: Int) -> PromptCategory? {
    if (5...11).contains(hour) { return .morning }
    if (18...22).contains(hour) { return .evening }
    if (23...23).contains(hour) || (0...4).contains(hour) { return .lateNight }
    return nil
  }

  func timeTitleKey(forHour hour: Int) -> String {
    switch Self.timeSubState(forHour: hour) {
    case .morning: return "prompts.cluster.time.title.morning"
    case .evening: return "prompts.cluster.time.title.evening"
    case .lateNight: return "prompts.cluster.time.title.late_night"
    default: return "prompts.cluster.time.title.morning"
    }
  }

  func timeSubtitleKey(forHour hour: Int) -> String {
    switch Self.timeSubState(forHour: hour) {
    case .morning: return "prompts.cluster.time.subtitle.morning"
    case .evening: return "prompts.cluster.time.subtitle.evening"
    case .lateNight: return "prompts.cluster.time.subtitle.late_night"
    default: return "prompts.cluster.time.subtitle.morning"
    }
  }

  func timeIllustration(forHour hour: Int) -> String {
    switch Self.timeSubState(forHour: hour) {
    case .morning: return "prompt_morning"
    case .evening: return "prompt_evening"
    case .lateNight: return "prompt_late_night"
    default: return "prompt_morning"
    }
  }

  func timeAiLensHint(forHour hour: Int) -> String {
    switch Self.timeSubState(forHour: hour) {
    case .morning: return "Direction: morning, start of day."
    case .evening: return "Direction: evening, end of day."
    case .lateNight: return "Direction: late night, unsettled, low capacity."
    default: return "Direction: time-of-day."
    }
  }
}

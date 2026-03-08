//
//  PromptCategory.swift
//  Sotie
//
//  Refactored on 17.05.2026 — clusters become the user-visible surface;
//  PromptCategory now serves as an internal sub-state ID for opener pools,
//  asset references, and analytics granularity.
//
//  See `PromptCluster` for the user-facing cluster grouping.
//

import Foundation

/// Internal sub-state of a `PromptCluster`. Drives:
///   - the localized opener pool (one per sub-state, 10 strings each)
///   - the asset name used for icon variety on the selected cluster card
///   - the second line of the AI seed-lens hint (`More specific: …`)
///
/// Sub-states are NEVER shown to the user as cards. The 21 cases are kept
/// for backward compatibility with persisted entries (`Entry.promptCategoryId`).
enum PromptCategory: String, CaseIterable, Codable, Sendable {
  // Time-bound (drive the time cluster's hour-of-day variant)
  case morning
  case evening
  case lateNight = "late_night"

  // Looping cluster sub-states
  case stuck
  case replay
  case restless

  // Heavy cluster sub-states
  case heavy
  case frustrated
  case numb
  case anxious

  // Choosing cluster sub-states
  case decision
  case change

  // Someone cluster sub-states
  case someone
  case youVsThem = "you_vs_them"

  // Notice cluster sub-states (positive + reflective)
  case wins
  case gratitude
  case patterns
  case futureSelf = "future_self"

  // Legacy: kept so old persisted `Entry.promptCategoryId` values still
  // decode. No longer surfaced — the Continue/Returning cards were removed
  // because each entry's AI conversation has no cross-entry memory.
  case returning
  case continueThread = "continue"

  // Brain dump cluster sub-state (the only one)
  case brainDump = "brain_dump"

  /// Stable identifier used for analytics + persistence.
  var id: String { rawValue }

  /// Asset catalog name for the sub-state illustration. The selected
  /// cluster card uses this to swap its icon based on the picked opener.
  var imageName: String { "prompt_\(rawValue)" }

  /// Localized title key — used by legacy code paths. New flow uses
  /// `PromptCluster.titleKey` instead.
  var titleKey: String { "prompts.category.\(rawValue).title" }

  /// Localized openers strings file key prefix. Each sub-state ships
  /// `prompts.openers.<rawValue>.<index>` keys (1-based).
  var openerKeyPrefix: String { "prompts.openers.\(rawValue)" }

  /// Short, directional second line of the AI seed-lens hint. Read as
  /// "More specific: …". Composes with the cluster's lens line when both
  /// exist; for single-sub-state clusters the cluster line stands alone.
  var aiLensHint: String {
    switch self {
    case .morning: return "More specific: morning."
    case .evening: return "More specific: evening."
    case .lateNight: return "More specific: late night."
    case .stuck: return "More specific: many threads pulling at once."
    case .replay: return "More specific: replaying a specific thought."
    case .heavy: return "More specific: heavy or sad."
    case .frustrated: return "More specific: angry or frustrated."
    case .numb: return "More specific: numb or blank."
    case .anxious: return "More specific: anxious."
    case .restless: return "More specific: restless or out of place."
    case .decision: return "More specific: a decision."
    case .someone: return "More specific: a single person."
    case .youVsThem: return "More specific: own wants vs others' expectations."
    case .change: return "More specific: a transition or change."
    case .wins: return "More specific: something that went well."
    case .gratitude: return "More specific: noticing what is already there."
    case .patterns: return "More specific: a recurring pattern."
    case .futureSelf: return "More specific: future self."
    case .returning: return "More specific: returning after a gap."
    case .continueThread: return "More specific: continuing a recent thread."
    case .brainDump: return "More specific: open dump."
    }
  }
}

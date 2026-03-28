//
//  PromptCatalog.swift
//  Sotie
//
//  Updated on 17.05.2026 — adds cluster-level opener picking on top of the
//  existing per-sub-state APIs.
//
//  Localized opener strings live in `Localizable.strings` under
//  `prompts.openers.<sub_state>.<index>` (1-based).
//

import Foundation

/// Resolves localized opener questions for a given prompt cluster or
/// sub-state.
///
/// Cluster-level callers (the AddEntry rail) draw an opener at random from
/// the union of the cluster's sub-state pools. The picked sub-state is
/// returned alongside the text and is used by the UI to swap the cluster
/// card's illustration (icon variety).
enum PromptCatalog {

  /// Number of openers shipped per sub-state. Add more by appending new
  /// `prompts.openers.<sub_state>.<n+1>` keys and bumping the count.
  static let openersPerCategory: [PromptCategory: Int] = [
    .morning: 10,
    .evening: 10,
    .lateNight: 10,
    .stuck: 10,
    .replay: 10,
    .heavy: 10,
    .frustrated: 10,
    .numb: 10,
    .anxious: 10,
    .restless: 10,
    .decision: 10,
    .someone: 10,
    .youVsThem: 10,
    .change: 10,
    .wins: 10,
    .gratitude: 10,
    .patterns: 10,
    .futureSelf: 10,
    .returning: 10,
    .continueThread: 10,
    .brainDump: 10,
  ]

  // MARK: - Sub-state APIs (kept for completeness + tests)

  /// All localized opener strings for a sub-state, in catalog order.
  static func openers(for category: PromptCategory, languageCode: String) -> [String] {
    let count = openersPerCategory[category] ?? 0
    guard count > 0 else { return [] }
    return (1...count).map { index in
      localizedString("\(category.openerKeyPrefix).\(index)", languageCode: languageCode)
    }
  }

  /// One opener picked deterministically from a single sub-state pool.
  /// Internal helper — most callers should use the cluster-level API below.
  static func opener(
    for category: PromptCategory,
    languageCode: String,
    seed: UInt64,
    recentlyShown: [Int] = []
  ) -> (index: Int, text: String) {
    let count = openersPerCategory[category] ?? 0
    guard count > 0 else { return (0, "") }

    let exclusionLimit = min(3, max(0, count - 1))
    let exclusions = Set(recentlyShown.suffix(exclusionLimit))
    let candidates = (1...count).filter { !exclusions.contains($0) }
    let pool = candidates.isEmpty ? Array(1...count) : candidates

    var rng = SeededRNG(seed: seed)
    let idx = pool[Int(rng.next() % UInt64(pool.count))]
    let text = localizedString("\(category.openerKeyPrefix).\(idx)", languageCode: languageCode)
    return (idx, text)
  }

  // MARK: - Cluster APIs

  /// Stable global index for cluster-level recency tracking.
  ///
  /// Encodes (sub-state, opener-within-pool) into a single `Int` so the VM
  /// can keep one "recently shown" array per cluster without caring which
  /// sub-state each pick came from. The picker only checks the last 3
  /// indices for exclusion, so collisions across very different schemes
  /// would not corrupt picking — they would just exclude a different
  /// candidate. The `subStateIndex * 100 + openerIndex` scheme is unique
  /// because no sub-state ships more than 99 openers.
  static func globalIndex(forSubState subState: PromptCategory, openerIndex: Int) -> Int {
    guard let subStateIndex = PromptCategory.allCases.firstIndex(of: subState) else {
      return openerIndex
    }
    return subStateIndex * 100 + openerIndex
  }

  /// Decode a global index back into its (sub-state, opener-within-pool)
  /// pair. Returns nil for malformed input.
  static func decodeGlobalIndex(_ globalIndex: Int) -> (subState: PromptCategory, openerIndex: Int)? {
    let subStateIndex = globalIndex / 100
    let openerIndex = globalIndex % 100
    guard subStateIndex >= 0, subStateIndex < PromptCategory.allCases.count else { return nil }
    let subState = PromptCategory.allCases[subStateIndex]
    return (subState, openerIndex)
  }

  /// All openers across a cluster's sub-states, tagged with their origin.
  /// Order: outer loop sub-states in declaration order, inner loop opener
  /// indices ascending. Stable for tests.
  static func openers(
    for cluster: PromptCluster,
    languageCode: String
  ) -> [(subState: PromptCategory, openerIndex: Int, text: String)] {
    var result: [(PromptCategory, Int, String)] = []
    for subState in cluster.subStates {
      let count = openersPerCategory[subState] ?? 0
      for index in 1...max(1, count) where count > 0 {
        let text = localizedString("\(subState.openerKeyPrefix).\(index)", languageCode: languageCode)
        result.append((subState, index, text))
      }
    }
    return result
  }

  /// Pick one opener from a cluster's union pool, deterministically by
  /// seed, excluding the last 3 globally-shown indices in `recentlyShownGlobalIndices`.
  ///
  /// For the time cluster, prefer `opener(forTime:languageCode:seed:recentlyShownGlobalIndices:)`
  /// — this method picks across ALL three time sub-states, which is wrong
  /// for the rail's hour-driven slot.
  static func opener(
    for cluster: PromptCluster,
    languageCode: String,
    seed: UInt64,
    recentlyShownGlobalIndices: [Int] = []
  ) -> (subState: PromptCategory, openerIndex: Int, text: String) {
    let candidates = openers(for: cluster, languageCode: languageCode)
    return pickWithExclusion(
      candidates: candidates,
      seed: seed,
      recentlyShownGlobalIndices: recentlyShownGlobalIndices
    )
  }

  /// Pick one opener from the time-cluster pool restricted to the
  /// hour-relevant sub-state (morning / evening / late-night). Returns
  /// `nil` when the hour falls into the midday gap (12-17), which the rail
  /// treats as "no time card today".
  static func opener(
    forTime hour: Int,
    languageCode: String,
    seed: UInt64,
    recentlyShownGlobalIndices: [Int] = []
  ) -> (subState: PromptCategory, openerIndex: Int, text: String)? {
    guard let subState = PromptCluster.timeSubState(forHour: hour) else { return nil }
    let count = openersPerCategory[subState] ?? 0
    guard count > 0 else { return nil }
    let candidates: [(PromptCategory, Int, String)] = (1...count).map { index in
      let text = localizedString("\(subState.openerKeyPrefix).\(index)", languageCode: languageCode)
      return (subState, index, text)
    }
    return pickWithExclusion(
      candidates: candidates,
      seed: seed,
      recentlyShownGlobalIndices: recentlyShownGlobalIndices
    )
  }

  // MARK: - Internal pick helper

  private static func pickWithExclusion(
    candidates: [(PromptCategory, Int, String)],
    seed: UInt64,
    recentlyShownGlobalIndices: [Int]
  ) -> (subState: PromptCategory, openerIndex: Int, text: String) {
    precondition(!candidates.isEmpty, "PromptCatalog.pickWithExclusion called with empty pool")

    let exclusionLimit = min(3, max(0, candidates.count - 1))
    let exclusions = Set(recentlyShownGlobalIndices.suffix(exclusionLimit))
    let filtered = candidates.filter { (subState, openerIndex, _) in
      let global = globalIndex(forSubState: subState, openerIndex: openerIndex)
      return !exclusions.contains(global)
    }
    let pool = filtered.isEmpty ? candidates : filtered

    var rng = SeededRNG(seed: seed)
    let pick = pool[Int(rng.next() % UInt64(pool.count))]
    return (pick.0, pick.1, pick.2)
  }
}

// MARK: - Deterministic RNG

/// A tiny SplitMix64 RNG, seeded for reproducibility within a session.
/// Used by both `PromptCatalog` (opener pick) and `PromptShuffler` (cluster
/// ordering) so identical seeds produce identical rails — important for
/// "show same cards if user reopens AddEntry" UX.
struct SeededRNG {
  private var state: UInt64

  init(seed: UInt64) {
    // Avoid all-zero state — SplitMix64 handles it but golden-ratio mixing
    // gives nicer distribution for tiny seeds.
    self.state = seed &+ 0x9E37_79B9_7F4A_7C15
  }

  mutating func next() -> UInt64 {
    state = state &+ 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

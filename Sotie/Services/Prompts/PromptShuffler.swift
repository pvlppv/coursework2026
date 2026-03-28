//
//  PromptShuffler.swift
//  Sotie
//
//  Rewritten on 17.05.2026 — Path A engagement-weighted ordering at the
//  cluster level (single signal: pick frequency in the last 14 days,
//  with a small recency decay). No content analysis, no time-of-day
//  learning, no balance heuristic, no cooldown.
//

import Foundation

/// Lightweight session context the shuffler needs.
struct PromptShuffleContext: Sendable {
  /// Hour of day (0-23). Drives the time-cluster slot.
  let hour: Int

  /// Day-of-year + entry count, used as the rotation seed. Same session
  /// reproduces the same rail; tomorrow's session differs.
  let rotationSeed: UInt64

  /// Whether today is a weekend (cold-start ordering varies slightly).
  let isWeekend: Bool

  /// User's recent cluster picks. Drives engagement-weighted ordering.
  let stats: ClusterStats

  /// Wall-clock now — used for recency decay scoring.
  let now: Date

  static func current(
    now: Date = Date(),
    entryCount: Int = 0,
    stats: ClusterStats = ClusterStats()
  ) -> PromptShuffleContext {
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: now)
    let dayOfYear = UInt64(calendar.ordinality(of: .day, in: .year, for: now) ?? 1)
    let seed = (dayOfYear &* 1_000_003) &+ UInt64(entryCount)
    let weekday = calendar.component(.weekday, from: now)
    return PromptShuffleContext(
      hour: hour,
      rotationSeed: seed,
      isWeekend: weekday == 1 || weekday == 7,
      stats: stats,
      now: now
    )
  }
}

/// Builds an ordered cluster rail from a shuffle context.
///
/// Rules, in priority order:
/// 1. Slot 1: time cluster, when the hour falls into a time window. At
///    midday (12-17) there is no time card; slot 1 falls through to the
///    highest-scored cluster.
/// 2. Last slot: brain dump (always, fixed).
/// 3. Middle slots: regular-rotation clusters sorted by engagement score,
///    minus already-used slots.
enum PromptShuffler {

  /// Number of cards rendered in the rail.
  static let railSize: Int = 6

  /// Build the rail for a given context. Pure — no I/O, no clock.
  static func buildRail(context: PromptShuffleContext) -> [PromptCluster] {
    var rail: [PromptCluster] = []
    var used: Set<PromptCluster> = []

    // Slot 1: time cluster (when applicable).
    if let timeCluster = PromptCluster.currentTimeCluster(forHour: context.hour) {
      rail.append(timeCluster)
      used.insert(timeCluster)
    }

    // Reserve last slot for brain dump.
    let middleSlotCount = max(0, railSize - rail.count - 1)

    // Middle slots: regular-rotation clusters by engagement score.
    let pool = PromptCluster.allCases.filter { cluster in
      cluster.isInRegularRotation && !used.contains(cluster)
    }
    let ordered: [PromptCluster]
    if context.stats.picks.count < 5 {
      // Cold start — use a stable default order until we have signal.
      ordered = coldStartOrder(isWeekend: context.isWeekend, pool: pool)
    } else {
      ordered = pool.sorted { lhs, rhs in
        score(cluster: lhs, in: context) > score(cluster: rhs, in: context)
      }
    }
    rail.append(contentsOf: ordered.prefix(middleSlotCount))

    // Last slot: brain dump.
    if !rail.contains(.brainDump) {
      rail.append(.brainDump)
    }

    return rail
  }

  // MARK: - Scoring (Path A)

  /// Engagement score for a cluster in a given context.
  /// Single signal + small recency decay:
  ///
  ///   score = pickFrequency(last14d) + 0.3 * recencyDecay
  ///
  /// `pickFrequency` is this cluster's share of all picks in the window.
  /// `recencyDecay` rewards "haven't seen lately" linearly from 1 day to
  /// 14 days. Capped to [0, 1] so a cluster picked yesterday gets 0
  /// recency boost and a never-picked cluster gets the full 0.3.
  static func score(cluster: PromptCluster, in context: PromptShuffleContext) -> Double {
    let windowStart = context.now.addingTimeInterval(-14 * 24 * 3600)
    let recentPicks = context.stats.picks.filter { $0.date >= windowStart }

    let totalPicks = max(1, recentPicks.count)
    let clusterPicks = recentPicks.filter { $0.cluster == cluster }.count
    let pickFrequency = Double(clusterPicks) / Double(totalPicks)

    let lastPickDate = recentPicks.last(where: { $0.cluster == cluster })?.date
    let daysSinceLast: Double
    if let lastPickDate {
      daysSinceLast = max(0, context.now.timeIntervalSince(lastPickDate) / (24 * 3600))
    } else {
      daysSinceLast = .infinity
    }
    let recencyDecay: Double
    if daysSinceLast.isInfinite {
      recencyDecay = 1.0
    } else {
      recencyDecay = max(0, min(1, (daysSinceLast - 1) / 14))
    }

    return pickFrequency + 0.3 * recencyDecay
  }

  // MARK: - Cold start

  /// Stable default order until the user has 5+ tracked picks. Weekday vs
  /// weekend swaps the last two slots so the rail doesn't feel identical
  /// every day even with no data.
  private static func coldStartOrder(
    isWeekend: Bool,
    pool: [PromptCluster]
  ) -> [PromptCluster] {
    let weekday: [PromptCluster] = [.heavy, .looping, .someone, .notice, .choosing]
    let weekend: [PromptCluster] = [.heavy, .looping, .someone, .choosing, .notice]
    let preferred = isWeekend ? weekend : weekday
    let preferredFiltered = preferred.filter(pool.contains)
    let leftover = pool.filter { !preferredFiltered.contains($0) }
    return preferredFiltered + leftover
  }
}

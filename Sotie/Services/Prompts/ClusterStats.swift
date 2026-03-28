//
//  ClusterStats.swift
//  Sotie
//
//
//  Persistent record of which prompt clusters the user has tapped, used
//  by `PromptShuffler` to weight the rail order.
//
//  Single signal: pickFrequency over a 14-day window + a small recency
//  decay (Path A — no cooldown, no balance heuristic, no time-of-day
//  learning). Capped at the last 60 picks to stay tiny in UserDefaults.
//

import Foundation
import os

/// Snapshot of recent cluster picks. Codable so we can round-trip through
/// UserDefaults; Sendable so the shuffler can copy it across actor hops.
struct ClusterStats: Codable, Sendable, Equatable {
  struct Pick: Codable, Sendable, Equatable {
    let cluster: PromptCluster
    let date: Date
  }

  var picks: [Pick]

  init(picks: [Pick] = []) {
    self.picks = picks
  }
}

/// UserDefaults-backed store for `ClusterStats`. Thread-safe by virtue of
/// `UserDefaults`'s own thread safety; no extra locks needed for the tiny
/// reads/writes this performs.
final class ClusterStatsStore: @unchecked Sendable {
  static let shared = ClusterStatsStore()

  /// Maximum picks retained. ~60 covers ~2 months of normal usage; older
  /// picks are dropped on append. Keeps UserDefaults blob under 4KB.
  static let maxPicks: Int = 60

  private let userDefaults: UserDefaults
  private let key: String

  init(
    userDefaults: UserDefaults = .standard,
    keyOverride: String? = nil
  ) {
    self.userDefaults = userDefaults
    self.key = keyOverride ?? "\(DeveloperConfig.appBundleID).promptClusterStats"
  }

  /// Loads the persisted stats. Empty stats on first launch or decode failure.
  func load() -> ClusterStats {
    guard let data = userDefaults.data(forKey: key) else {
      return ClusterStats()
    }
    do {
      return try JSONDecoder().decode(ClusterStats.self, from: data)
    } catch {
      AppLogger.data.warning("ClusterStats decode failed: \(error.localizedDescription); resetting")
      return ClusterStats()
    }
  }

  /// Records a cluster pick at the given date (defaults to now). Trims the
  /// list to the last `maxPicks` entries before persisting.
  func recordPick(_ cluster: PromptCluster, at date: Date = Date()) {
    var stats = load()
    stats.picks.append(.init(cluster: cluster, date: date))
    if stats.picks.count > Self.maxPicks {
      stats.picks.removeFirst(stats.picks.count - Self.maxPicks)
    }
    persist(stats)
  }

  /// Removes all stored picks. Used by tests and "reset analytics" flows.
  func clear() {
    userDefaults.removeObject(forKey: key)
  }

  private func persist(_ stats: ClusterStats) {
    do {
      let data = try JSONEncoder().encode(stats)
      userDefaults.set(data, forKey: key)
    } catch {
      AppLogger.data.error("ClusterStats encode failed: \(error.localizedDescription)")
    }
  }
}

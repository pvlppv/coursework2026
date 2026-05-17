import Foundation
import Testing

@testable import Sotie

@MainActor
struct ClusterStatsStoreTests {

  /// Build a store with an isolated UserDefaults suite so tests don't
  /// pollute the real user's state.
  private func makeStore(_ suiteName: String) throws -> (ClusterStatsStore, UserDefaults) {
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = ClusterStatsStore(userDefaults: defaults, keyOverride: "test.clusterStats")
    return (store, defaults)
  }

  @Test func loadReturnsEmptyOnFirstUse() async throws {
    let (store, defaults) = try makeStore("ClusterStatsStoreTests.empty")
    defer { defaults.removePersistentDomain(forName: "ClusterStatsStoreTests.empty") }
    #expect(store.load().picks.isEmpty)
  }

  @Test func recordPickRoundTrips() async throws {
    let (store, defaults) = try makeStore("ClusterStatsStoreTests.roundTrip")
    defer { defaults.removePersistentDomain(forName: "ClusterStatsStoreTests.roundTrip") }
    let now = Date()
    store.recordPick(.heavy, at: now)
    store.recordPick(.looping, at: now.addingTimeInterval(60))
    let stats = store.load()
    #expect(stats.picks.count == 2)
    #expect(stats.picks[0].cluster == .heavy)
    #expect(stats.picks[1].cluster == .looping)
  }

  @Test func picksAreCappedAtSixty() async throws {
    let (store, defaults) = try makeStore("ClusterStatsStoreTests.cap")
    defer { defaults.removePersistentDomain(forName: "ClusterStatsStoreTests.cap") }
    let base = Date()
    for i in 0..<70 {
      store.recordPick(.heavy, at: base.addingTimeInterval(Double(i)))
    }
    let stats = store.load()
    #expect(stats.picks.count == 60)
    // The oldest 10 should have been dropped — first remaining pick has
    // index 10 (i.e., timestamp base + 10 seconds).
    #expect(stats.picks.first?.date == base.addingTimeInterval(10))
  }

  @Test func clearEmptiesPicks() async throws {
    let (store, defaults) = try makeStore("ClusterStatsStoreTests.clear")
    defer { defaults.removePersistentDomain(forName: "ClusterStatsStoreTests.clear") }
    store.recordPick(.someone)
    store.recordPick(.choosing)
    store.clear()
    #expect(store.load().picks.isEmpty)
  }
}

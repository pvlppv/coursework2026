import Foundation
import Testing

@testable import Sotie

@MainActor
struct PromptShufflerTests {

  private func ctx(
    hour: Int,
    isWeekend: Bool = false,
    stats: ClusterStats = ClusterStats(),
    now: Date = Date()
  ) -> PromptShuffleContext {
    PromptShuffleContext(
      hour: hour,
      rotationSeed: 0,
      isWeekend: isWeekend,
      stats: stats,
      now: now
    )
  }

  @Test func railSizeIsAlwaysSix() async throws {
    for hour in 0..<24 {
      let rail = PromptShuffler.buildRail(context: ctx(hour: hour))
      #expect(rail.count == PromptShuffler.railSize)
    }
  }

  @Test func slotOneIsTimeWhenInWindow() async throws {
    for hour in [6, 8, 11, 18, 20, 22, 23, 0, 2, 4] {
      let rail = PromptShuffler.buildRail(context: ctx(hour: hour))
      #expect(rail.first == .time, "hour \(hour) should produce a time slot")
    }
  }

  @Test func slotOneIsNotTimeAtMidday() async throws {
    for hour in 12...17 {
      let rail = PromptShuffler.buildRail(context: ctx(hour: hour))
      #expect(rail.first != .time, "hour \(hour) should not produce a time slot")
    }
  }

  @Test func lastSlotIsAlwaysBrainDump() async throws {
    for hour in 0..<24 {
      let rail = PromptShuffler.buildRail(context: ctx(hour: hour))
      #expect(rail.last == .brainDump)
    }
  }

  @Test func coldStartWeekdayOrderIsStable() async throws {
    // Tuesday — weekday. With time slot at 8am, expect:
    //   [time, heavy, looping, someone, notice, brainDump]
    let rail = PromptShuffler.buildRail(context: ctx(hour: 8, isWeekend: false))
    #expect(rail == [.time, .heavy, .looping, .someone, .notice, .brainDump])
  }

  @Test func coldStartMiddayWeekdayOrderHasNoTime() async throws {
    // Midday weekday: slot 1 falls through. Expect:
    //   [heavy, looping, someone, notice, choosing, brainDump]
    let rail = PromptShuffler.buildRail(context: ctx(hour: 14, isWeekend: false))
    #expect(rail == [.heavy, .looping, .someone, .notice, .choosing, .brainDump])
  }

  @Test func coldStartWeekendSwapsLastTwo() async throws {
    let weekday = PromptShuffler.buildRail(context: ctx(hour: 14, isWeekend: false))
    let weekend = PromptShuffler.buildRail(context: ctx(hour: 14, isWeekend: true))
    // Weekday: notice before choosing. Weekend: choosing before notice.
    #expect(weekday[3] == .notice && weekday[4] == .choosing)
    #expect(weekend[3] == .choosing && weekend[4] == .notice)
  }

  @Test func clusterPickedFiveTimesOutranksClusterPickedOnce() async throws {
    let now = Date()
    let oneHourAgo = now.addingTimeInterval(-3600)
    let picks: [ClusterStats.Pick] =
      Array(repeating: ClusterStats.Pick(cluster: .choosing, date: oneHourAgo), count: 5)
      + [ClusterStats.Pick(cluster: .heavy, date: oneHourAgo)]
    let stats = ClusterStats(picks: picks)
    let rail = PromptShuffler.buildRail(context: ctx(hour: 14, stats: stats, now: now))

    // Choosing should appear before Heavy in the middle slots.
    let middle = Array(rail.dropFirst(0).dropLast())  // strip brainDump
    let choosingIdx = middle.firstIndex(of: .choosing)
    let heavyIdx = middle.firstIndex(of: .heavy)
    #expect(choosingIdx != nil && heavyIdx != nil)
    if let c = choosingIdx, let h = heavyIdx {
      #expect(c < h, "choosing (5 picks) should outrank heavy (1 pick)")
    }
  }

  @Test func scoreFavorsFrequentClusterOverIdleOne() async throws {
    let now = Date()
    let stats = ClusterStats(picks: [
      .init(cluster: .heavy, date: now.addingTimeInterval(-3600)),
      .init(cluster: .heavy, date: now.addingTimeInterval(-3600 * 2)),
      .init(cluster: .heavy, date: now.addingTimeInterval(-3600 * 3)),
      .init(cluster: .looping, date: now.addingTimeInterval(-3600 * 24 * 10)),
    ])
    let context = ctx(hour: 14, stats: stats, now: now)
    let heavyScore = PromptShuffler.score(cluster: .heavy, in: context)
    let loopingScore = PromptShuffler.score(cluster: .looping, in: context)
    #expect(heavyScore > loopingScore)
  }
}

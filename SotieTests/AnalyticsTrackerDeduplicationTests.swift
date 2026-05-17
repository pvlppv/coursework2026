import Foundation
import SwiftData
import Testing

@testable import Sotie

@MainActor
@Suite(.serialized)
struct AnalyticsTrackerDeduplicationTests {

  @Test func initializeMergesDuplicateAnalyticsRowsInsteadOfDroppingHigherCounters() throws {
    let container = try ModelContainer(
      for: Entry.self,
      AnalyticsData.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let higherTime = AnalyticsData()
    higherTime.totalSecondsSpent = 600
    higherTime.totalAIResponsesGenerated = 1
    higherTime.totalUserResponses = 1
    higherTime.totalConversations = 1

    let higherCounts = AnalyticsData()
    higherCounts.totalSecondsSpent = 120
    higherCounts.totalAIResponsesGenerated = 9
    higherCounts.totalUserResponses = 7
    higherCounts.totalConversations = 4

    context.insert(higherTime)
    context.insert(higherCounts)
    try context.save()

    AnalyticsTracker.shared.initialize(with: context)

    let remaining = try context.fetch(FetchDescriptor<AnalyticsData>())
    #expect(remaining.count == 1)

    let canonical = try #require(remaining.first)
    #expect(canonical.totalSecondsSpent == 600)
    #expect(canonical.totalAIResponsesGenerated == 9)
    #expect(canonical.totalUserResponses == 7)
    #expect(canonical.totalConversations == 4)
  }

  @Test func recoveredDurationDoesNotCountBackgroundIdleWhenSessionWasPaused() {
    let recovered = AnalyticsTracker.recoveredDuration(
      startTimestamp: nil,
      accumulated: 120,
      now: Date(timeIntervalSince1970: 1_700_000_300)
    )

    #expect(recovered == 120)
  }
}

import Foundation
import SwiftData
import Testing

@testable import Sotie

@MainActor
struct ExportManagerStatisticsTests {

  @Test func exportMergesDuplicateAnalyticsRecordsIntoOneCanonicalPayload() throws {
    let container = try ModelContainer(
      for: Entry.self,
      AnalyticsData.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let first = AnalyticsData()
    first.totalSecondsSpent = 120
    first.totalAIResponsesGenerated = 2
    first.totalUserResponses = 1
    first.totalConversations = 1

    let second = AnalyticsData()
    second.totalSecondsSpent = 90
    second.totalAIResponsesGenerated = 5
    second.totalUserResponses = 4
    second.totalConversations = 3

    context.insert(first)
    context.insert(second)
    try context.save()

    let document = try ExportManager(modelContext: context).exportEntries()
    let analytics = try #require(document.exportData.analytics)

    #expect(analytics.totalSecondsSpent == 120)
    #expect(analytics.totalAIResponsesGenerated == 5)
    #expect(analytics.totalUserResponses == 4)
    #expect(analytics.totalConversations == 3)
  }
}

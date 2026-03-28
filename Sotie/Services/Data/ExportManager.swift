import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Supporting Types (must be defined before @MainActor class)

nonisolated struct ExportData: Codable, Sendable {
  let exportedAt: Date
  let version: String
  let entries: [ExportedEntry]
  let analytics: ExportedAnalytics?

  // Backward-compatible decoding for files exported before analytics was added
  enum CodingKeys: String, CodingKey {
    case exportedAt, version, entries, analytics
  }

  init(exportedAt: Date, version: String, entries: [ExportedEntry], analytics: ExportedAnalytics?) {
    self.exportedAt = exportedAt
    self.version = version
    self.entries = entries
    self.analytics = analytics
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    exportedAt = try container.decode(Date.self, forKey: .exportedAt)
    version = try container.decode(String.self, forKey: .version)
    entries = try container.decode([ExportedEntry].self, forKey: .entries)
    analytics = try container.decodeIfPresent(ExportedAnalytics.self, forKey: .analytics)
  }
}

nonisolated struct ExportedEntry: Codable, Sendable {
  let id: UUID
  let date: Date
  let observation: String
  let comment: String?
  let extractedValue: Double?
  let originalEntryText: String?

  // AI Conversation data
  let conversation: [DialogueMessage]
  let conversationSummary: ConversationSummary?

  // Insights (takeaway)
  let insights: ConversationInsights?

  // Prompt metadata
  let promptText: String?
  let promptClusterId: String?
  let promptCategoryId: String?
  let promptOpenerIndex: Int?

  // Notification tracking
  let notificationSentAt: Date?

  // Backward-compatible decoding for files exported before new fields were added
  enum CodingKeys: String, CodingKey {
    case id, date, observation, comment, extractedValue, originalEntryText
    case conversation, conversationSummary, insights
    case promptText, promptClusterId, promptCategoryId, promptOpenerIndex
    case notificationSentAt
  }

  init(id: UUID, date: Date, observation: String, comment: String?, extractedValue: Double?, originalEntryText: String?, conversation: [DialogueMessage], conversationSummary: ConversationSummary?, insights: ConversationInsights?, promptText: String?, promptClusterId: String?, promptCategoryId: String?, promptOpenerIndex: Int?, notificationSentAt: Date?) {
    self.id = id
    self.date = date
    self.observation = observation
    self.comment = comment
    self.extractedValue = extractedValue
    self.originalEntryText = originalEntryText
    self.conversation = conversation
    self.conversationSummary = conversationSummary
    self.insights = insights
    self.promptText = promptText
    self.promptClusterId = promptClusterId
    self.promptCategoryId = promptCategoryId
    self.promptOpenerIndex = promptOpenerIndex
    self.notificationSentAt = notificationSentAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    date = try container.decode(Date.self, forKey: .date)
    observation = try container.decode(String.self, forKey: .observation)
    comment = try container.decodeIfPresent(String.self, forKey: .comment)
    extractedValue = try container.decodeIfPresent(Double.self, forKey: .extractedValue)
    originalEntryText = try container.decodeIfPresent(String.self, forKey: .originalEntryText)
    conversation = try container.decodeIfPresent([DialogueMessage].self, forKey: .conversation) ?? []
    conversationSummary = try container.decodeIfPresent(ConversationSummary.self, forKey: .conversationSummary)
    insights = try container.decodeIfPresent(ConversationInsights.self, forKey: .insights)
    promptText = try container.decodeIfPresent(String.self, forKey: .promptText)
    promptClusterId = try container.decodeIfPresent(String.self, forKey: .promptClusterId)
    promptCategoryId = try container.decodeIfPresent(String.self, forKey: .promptCategoryId)
    promptOpenerIndex = try container.decodeIfPresent(Int.self, forKey: .promptOpenerIndex)
    notificationSentAt = try container.decodeIfPresent(Date.self, forKey: .notificationSentAt)
  }
}

nonisolated struct ExportedAnalytics: Codable, Sendable {
  let totalSecondsSpent: Double
  let totalAIResponsesGenerated: Int
  let totalUserResponses: Int
  let totalConversations: Int
}

struct ImportResult: Sendable {
  let importedEntriesCount: Int
  let skippedEntriesCount: Int

  var message: String {
    if skippedEntriesCount == 0 {
      return appLocalizedString(Localizable.importEntriesImported, arguments: importedEntriesCount)
    } else {
      return appLocalizedString(
        Localizable.importEntriesImportedSkipped,
        arguments: importedEntriesCount, skippedEntriesCount
      )
    }
  }
}

/// Manager for importing and exporting entries to JSON files
@MainActor
final class ExportManager {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  // MARK: - Export

  func exportEntries() throws -> ExportDocument {
    // Fetch all entries
    let descriptor = FetchDescriptor<Entry>(
      sortBy: [SortDescriptor(\.date, order: .reverse)]
    )
    let entries = try modelContext.fetch(descriptor)

    // Convert entries to exportable format
    let exportedEntries = entries.map { entry in
      ExportedEntry(
        id: entry.id,
        date: entry.date,
        observation: entry.observation,
        comment: entry.comment,
        extractedValue: entry.extractedValue,
        originalEntryText: entry.originalEntryText,
        conversation: entry.conversation,
        conversationSummary: entry.conversationSummary,
        insights: entry.insights,
        promptText: entry.promptText,
        promptClusterId: entry.promptClusterId,
        promptCategoryId: entry.promptCategoryId,
        promptOpenerIndex: entry.promptOpenerIndex,
        notificationSentAt: entry.notificationSentAt
      )
    }

    // Export analytics
    let analyticsDescriptor = FetchDescriptor<AnalyticsData>()
    let analyticsRecords = try modelContext.fetch(analyticsDescriptor)
    let exportedAnalytics = StatisticsCalculator.mergedAnalytics(from: analyticsRecords)

    let exportData = ExportData(
      exportedAt: Date(),
      version: "1.2",
      entries: exportedEntries,
      analytics: exportedAnalytics
    )

    return ExportDocument(exportData: exportData)
  }

  // MARK: - Import

  func importEntries(from document: ExportDocument) throws -> ImportResult {
    let exportData = document.exportData

    // Fetch existing entries to check for duplicates
    let entryDescriptor = FetchDescriptor<Entry>()
    let existingEntries = try modelContext.fetch(entryDescriptor)
    let existingEntryIds = Set(existingEntries.map { $0.id })

    var importedEntriesCount = 0
    var skippedEntriesCount = 0

    // Import entries
    for exportedEntry in exportData.entries {
      // Skip if entry already exists
      if existingEntryIds.contains(exportedEntry.id) {
        skippedEntriesCount += 1
        continue
      }

      // Create entry
      let entry = Entry(
        observation: exportedEntry.observation,
        comment: exportedEntry.comment,
        date: exportedEntry.date,
        extractedValue: exportedEntry.extractedValue
      )
      entry.id = exportedEntry.id

      // Restore original entry text (Blocker fix)
      if let originalText = exportedEntry.originalEntryText {
        entry.originalEntryText = originalText
      }

      // Restore conversation data
      if !exportedEntry.conversation.isEmpty {
        entry.conversation = exportedEntry.conversation
        // hasActiveConversation is set by the conversation setter
      }

      // Restore conversation summary
      if let summary = exportedEntry.conversationSummary {
        entry.conversationSummary = summary
      }

      // Restore insights (takeaway)
      if let insights = exportedEntry.insights {
        entry.insights = insights
      }

      // Restore prompt metadata
      entry.promptText = exportedEntry.promptText
      entry.promptClusterId = exportedEntry.promptClusterId
      entry.promptCategoryId = exportedEntry.promptCategoryId
      entry.promptOpenerIndex = exportedEntry.promptOpenerIndex

      // Restore notification tracking
      entry.notificationSentAt = exportedEntry.notificationSentAt

      modelContext.insert(entry)
      importedEntriesCount += 1
    }

    // Import analytics (replace — use max to handle repeated imports safely)
    if let exportedAnalytics = exportData.analytics {
      let analyticsDescriptor = FetchDescriptor<AnalyticsData>()
      let existing = try modelContext.fetch(analyticsDescriptor)
      let analytics = existing.first ?? AnalyticsData()
      if existing.isEmpty {
        modelContext.insert(analytics)
      }
      analytics.totalSecondsSpent = max(analytics.totalSecondsSpent, exportedAnalytics.totalSecondsSpent)
      analytics.totalAIResponsesGenerated = max(analytics.totalAIResponsesGenerated, exportedAnalytics.totalAIResponsesGenerated)
      analytics.totalUserResponses = max(analytics.totalUserResponses, exportedAnalytics.totalUserResponses)
      analytics.totalConversations = max(analytics.totalConversations, exportedAnalytics.totalConversations)
    }

    // Save changes
    try modelContext.save()

    return ImportResult(
      importedEntriesCount: importedEntriesCount,
      skippedEntriesCount: skippedEntriesCount
    )
  }
}

// MARK: - Document Type

struct ExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }

  var exportData: ExportData

  init(exportData: ExportData) {
    self.exportData = exportData
  }

  nonisolated init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    exportData = try decoder.decode(ExportData.self, from: data)
  }

  nonisolated func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let data = try encoder.encode(exportData)
    return FileWrapper(regularFileWithContents: data)
  }
}

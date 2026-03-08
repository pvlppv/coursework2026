import Foundation
import os
import SwiftData

@Model
final class Entry {
  @Attribute(.unique) var id: UUID
  var date: Date = Date()
  var observation: String = ""
  var comment: String?
  var extractedValue: Double?

  /// The unmodified first observation text that started this entry.
  /// This is the canonical "original entry" used end-to-end:
  /// Go Deeper prompt anchor, notification prompts, and any surface
  /// that needs "what the user originally wrote".
  /// nil for entries created before this field existed — use `canonicalOriginalText` instead.
  var originalEntryText: String?

  /// The localized opener text the user picked from the prompt rail to seed
  /// this entry, if any. Kept verbatim so we can render it as the first
  /// AI message even when the localization changes later.
  /// nil = entry started without a prompt.
  var promptText: String?

  /// Stable rawValue of the `PromptCluster` that produced `promptText`.
  /// New-flow analytics + future per-cluster personalization. nil for
  /// entries started without a prompt or created before this field existed.
  var promptClusterId: String?

  /// Stable rawValue of the `PromptCategory` (sub-state) used to draw the
  /// opener. Drives icon variety on the selected card and preserves
  /// per-sub-state analytics granularity even though the rail collapses
  /// these into clusters. Mirrors the legacy field name from when each
  /// sub-state was its own card.
  var promptCategoryId: String?

  /// 1-based index of the opener within its sub-state pool. Used to track
  /// which openers fire most so we can prune low-performers later. nil for
  /// entries without a seeded prompt.
  var promptOpenerIndex: Int?

  // Notification tracking
  var notificationSentAt: Date?


  // GoDeeper conversation
  var conversationJSON: String = "[]"  // JSON array of DialogueMessage
  var hasActiveConversation: Bool = false
  var conversationSummaryJSON: String?  // JSON of ConversationSummary
  var insightsJSON: String?  // JSON of ConversationInsights

  /// In-memory cache of decoded conversation messages.
  /// Avoids repeated JSON decoding on every property access (3+ times per card in feed).
  @Transient private var _conversationCache: [DialogueMessage]?
  @Transient private var _conversationCacheKey: String?

  var conversation: [DialogueMessage] {
    get {
      // Serve from cache if the underlying JSON hasn't changed
      if let cached = _conversationCache, _conversationCacheKey == conversationJSON {
        return cached
      }
      guard let data = conversationJSON.data(using: .utf8), !conversationJSON.isEmpty else {
        _conversationCache = []
        _conversationCacheKey = conversationJSON
        return []
      }
      do {
        let decoded = try JSONDecoder().decode([DialogueMessage].self, from: data)
        _conversationCache = decoded
        _conversationCacheKey = conversationJSON
        return decoded
      } catch {
        AppLogger.data.error("conversationJSON decode failed for entry \(self.id): \(error.localizedDescription)")
        _conversationCache = []
        _conversationCacheKey = conversationJSON
        return []
      }
    }
    set {
      do {
        let data = try JSONEncoder().encode(newValue)
        conversationJSON = String(data: data, encoding: .utf8) ?? "[]"
      } catch {
        AppLogger.data.error("conversationJSON encode failed for entry \(self.id): \(error.localizedDescription)")
        conversationJSON = "[]"
      }
      // Update cache immediately — no need to re-decode what we just set
      _conversationCache = newValue
      _conversationCacheKey = conversationJSON
      hasActiveConversation = !newValue.isEmpty
    }
  }

  var conversationSummary: ConversationSummary? {
    get {
      guard let json = conversationSummaryJSON,
        let data = json.data(using: .utf8)
      else {
        return nil
      }
      do {
        return try JSONDecoder().decode(ConversationSummary.self, from: data)
      } catch {
        // Log corruption — don't silently mask decode failures
        AppLogger.data.error("conversationSummaryJSON decode failed for entry \(self.id): \(error.localizedDescription)")
        return nil
      }
    }
    set {
      if let summary = newValue,
        let data = try? JSONEncoder().encode(summary),
        let json = String(data: data, encoding: .utf8)
      {
        conversationSummaryJSON = json
      } else {
        conversationSummaryJSON = nil
      }
    }
  }

  var insights: ConversationInsights? {
    get {
      guard let json = insightsJSON,
        let data = json.data(using: .utf8),
        let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let whatHappened = dict["whatHappened"] as? String,
        let whatsUnderneath = dict["whatsUnderneath"] as? String,
        let whatMattersNow = dict["whatMattersNow"] as? String,
        let messageCount = dict["messageCount"] as? Int
      else {
        return nil
      }
      let generatedAt: Date
      if let timestamp = dict["generatedAt"] as? Double {
        generatedAt = Date(timeIntervalSinceReferenceDate: timestamp)
      } else {
        generatedAt = Date()
      }
      return ConversationInsights(
        whatHappened: whatHappened,
        whatsUnderneath: whatsUnderneath,
        whatMattersNow: whatMattersNow,
        messageCount: messageCount,
        generatedAt: generatedAt
      )
    }
    set {
      if let insights = newValue {
        let dict: [String: Any] = [
          "whatHappened": insights.whatHappened,
          "whatsUnderneath": insights.whatsUnderneath,
          "whatMattersNow": insights.whatMattersNow,
          "messageCount": insights.messageCount,
          "generatedAt": insights.generatedAt.timeIntervalSinceReferenceDate
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict),
          let json = String(data: data, encoding: .utf8)
        {
          insightsJSON = json
        } else {
          insightsJSON = nil
        }
      } else {
        insightsJSON = nil
      }
    }
  }

  // No relationships - entries are standalone

  init(
    observation: String,
    comment: String? = nil,
    date: Date = Date(),
    extractedValue: Double? = nil,
    // photoURLs: [String] = [],
    // voiceRecordingURL: String? = nil
  ) {
    self.id = UUID()
    self.observation = observation
    self.originalEntryText = observation
    self.comment = comment
    self.date = date
    self.extractedValue = extractedValue
  }

  // Computed properties for entry type detection

  var isMediaEntry: Bool {
    false
  }

  /// Whether a follow-up notification has been sent and the user hasn't opened this entry yet.
  var hasActiveNotification: Bool {
    notificationSentAt != nil
  }

  /// The last AI response from the Go Deeper conversation (zero-cost extraction).
  /// Used on entry cards and in follow-up notifications.
  var lastAIResponse: String? {
    conversation.last(where: { $0.role == .assistant })?.content
  }

  /// Canonical original text — backward-compatible accessor.
  /// Returns `originalEntryText` for new entries, falls back to first user message
  /// or observation for legacy entries created before the field existed.
  var canonicalOriginalText: String {
    if let original = originalEntryText, !original.isEmpty {
      return original
    }
    // Legacy fallback: first user message from conversation, or observation
    if let firstUserMessage = conversation.first(where: { $0.role == .user }) {
      return firstUserMessage.content
    }
    return observation
  }

  var primaryContent: String {
    if !observation.isEmpty {
      return observation
    } else {
      return appLocalizedString(Localizable.entryText)
    }
  }
}

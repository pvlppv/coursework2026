import Foundation

/// Structured insights generated at the end of a reflection conversation.
/// Stored on the Entry and viewable later from the entry menu.
///
/// Note: This struct is intentionally nonisolated and Sendable. It is used across
/// actor boundaries (stored on @MainActor Entry, created by backend AI transport).
/// The explicit CodingKeys and init(from:) ensure Swift 6 doesn't infer @MainActor
/// on the Codable conformance from usage in @Model contexts.
struct ConversationInsights: Hashable, Sendable {

  /// One-line summary of the situation the user described.
  let whatHappened: String

  /// The feeling, assumption, or pattern the AI noticed underneath.
  let whatsUnderneath: String

  /// One actionable reframe or next step.
  let whatMattersNow: String

  /// Number of conversation messages at the time insights were generated.
  /// Used for staleness detection: if current conversation.count != this, regenerate.
  let messageCount: Int

  /// Timestamp when these insights were generated.
  let generatedAt: Date

  nonisolated init(
    whatHappened: String,
    whatsUnderneath: String,
    whatMattersNow: String,
    messageCount: Int,
    generatedAt: Date = Date()
  ) {
    self.whatHappened = whatHappened
    self.whatsUnderneath = whatsUnderneath
    self.whatMattersNow = whatMattersNow
    self.messageCount = messageCount
    self.generatedAt = generatedAt
  }

  /// Whether these insights are stale relative to the current conversation state.
  func isStale(currentMessageCount: Int) -> Bool {
    return messageCount != currentMessageCount
  }
}

// MARK: - Codable (explicit, nonisolated conformance to prevent @MainActor inference)

extension ConversationInsights: Codable {
  private enum CodingKeys: String, CodingKey {
    case whatHappened, whatsUnderneath, whatMattersNow, messageCount, generatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    whatHappened = try container.decode(String.self, forKey: .whatHappened)
    whatsUnderneath = try container.decode(String.self, forKey: .whatsUnderneath)
    whatMattersNow = try container.decode(String.self, forKey: .whatMattersNow)
    messageCount = try container.decode(Int.self, forKey: .messageCount)
    generatedAt = try container.decode(Date.self, forKey: .generatedAt)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(whatHappened, forKey: .whatHappened)
    try container.encode(whatsUnderneath, forKey: .whatsUnderneath)
    try container.encode(whatMattersNow, forKey: .whatMattersNow)
    try container.encode(messageCount, forKey: .messageCount)
    try container.encode(generatedAt, forKey: .generatedAt)
  }
}

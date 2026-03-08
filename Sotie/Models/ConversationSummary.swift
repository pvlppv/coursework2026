import Foundation

/// Quality of signal extracted from the conversation
enum SignalQuality: String, Hashable, Sendable, Codable {
  /// Rich, multi-sentence responses with emotional/cognitive content
  case strong
  /// Mixed — some depth but also minimal responses
  case moderate
  /// Mostly one-word or minimal responses (ok, da, ne znayu) — not enough data for confident insights
  case insufficient
}

/// Represents compact memory for a Go Deeper conversation.
/// Designed to preserve useful context while keeping future responses tentative and grounded.
struct ConversationSummary: Hashable, Sendable {

  // MARK: - Properties

  /// The original core entry text (always preserved)
  let coreEntryText: String

  /// Tentative core: what seems to matter most, grounded in the user's words.
  let coreInsight: String

  /// Possible next openings, unresolved tensions, or useful reminders for the next response.
  let nextOpenings: String?

  /// Compact Go Deeper routing state: topic, loop shape, emotional tone, need, outcome, intensity, and safety.
  let routingState: String?

  /// Guidance for the next response shape/component, expressed as tentative context rather than an instruction.
  let responseGuidance: String?

  /// Signals that the reflection may have landed or should slow down/stop instead of digging further.
  let stopSignals: [String]

  /// Angles, frames, or moves that did not help and should not be repeated.
  let failedAngles: [String]

  /// Quality of signal from the user's responses.
  /// When insufficient, downstream consumers should treat insights as tentative.
  let signalQuality: SignalQuality

  /// Angles/perspectives already covered in the conversation
  /// Helps AI avoid repetitive questions
  let anglesCovered: [String]

  /// Short direct quotes from user responses that anchor the coreInsight
  /// Prevents drift in incremental summarization
  let evidenceTail: [String]

  /// Number of messages that were summarized
  let summarizedMessageCount: Int

  /// Timestamp when this summary was created
  let createdAt: Date

  /// Total conversation message count at time of summarization
  let totalMessageCount: Int

  // MARK: - Initialization

  nonisolated init(
    coreEntryText: String,
    coreInsight: String,
    nextOpenings: String? = nil,
    routingState: String? = nil,
    responseGuidance: String? = nil,
    stopSignals: [String] = [],
    failedAngles: [String] = [],
    signalQuality: SignalQuality = .strong,
    anglesCovered: [String] = [],
    evidenceTail: [String] = [],
    summarizedMessageCount: Int,
    totalMessageCount: Int,
    createdAt: Date = Date()
  ) {
    self.coreEntryText = coreEntryText
    self.coreInsight = coreInsight
    self.nextOpenings = nextOpenings
    self.routingState = routingState
    self.responseGuidance = responseGuidance
    self.stopSignals = stopSignals
    self.failedAngles = failedAngles
    self.signalQuality = signalQuality
    self.anglesCovered = anglesCovered
    self.evidenceTail = evidenceTail
    self.summarizedMessageCount = summarizedMessageCount
    self.totalMessageCount = totalMessageCount
    self.createdAt = createdAt
  }

  // MARK: - Formatted Output

  /// Generates formatted text for inclusion in AI prompts.
  /// Presents summary data as tentative context, not instructions.
  nonisolated var formattedForPrompt: String {
    var formatted = ""

    // When signal is insufficient, flag it so the response engine doesn't over-trust the summary
    if signalQuality == .insufficient {
      formatted += "LOW SIGNAL - user gave mostly minimal responses (ok, yes, don't know). Treat insights below as tentative, not confirmed. Draw out more signal instead of building on uncertain assumptions.\n\n"
    }

    formatted += "TENTATIVE CORE - verify against recent exchange:\n" + coreInsight

    if let routing = routingState, !routing.isEmpty {
      formatted += "\n\nROUTING STATE - tentative, latest user message wins:\n"
      formatted += routing
    }

    if let guidance = responseGuidance, !guidance.isEmpty {
      formatted += "\n\nRESPONSE GUIDANCE - context, not commands:\n"
      formatted += guidance
    }

    if !evidenceTail.isEmpty {
      formatted += "\n\nEVIDENCE - user's own words:\n"
      formatted += evidenceTail.map { "- \"\($0)\"" }.joined(separator: "\n")
    }

    if let openings = nextOpenings, !openings.isEmpty {
      formatted += "\n\nPOSSIBLE NEXT OPENINGS - context, not commands:\n"
      formatted += openings
    }

    if !stopSignals.isEmpty {
      formatted += "\n\nSTOP / CONSOLIDATE SIGNALS - do not reopen if still true:\n"
      formatted += stopSignals.joined(separator: ", ")
    }

    if !failedAngles.isEmpty {
      formatted += "\n\nFAILED OR REJECTED ANGLES - avoid repeating:\n"
      formatted += failedAngles.joined(separator: ", ")
    }

    if !anglesCovered.isEmpty {
      formatted += "\n\nANGLES ALREADY EXPLORED - avoid repeating unless user returns there:\n"
      formatted += anglesCovered.joined(separator: ", ")
    }

    return formatted
  }
}

// MARK: - Codable Conformance

extension ConversationSummary: Codable {
  nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.coreEntryText = try container.decode(String.self, forKey: .coreEntryText)
    self.coreInsight = try container.decode(String.self, forKey: .coreInsight)
    self.nextOpenings = try container.decodeIfPresent(String.self, forKey: .nextOpenings)
    self.routingState = try container.decodeIfPresent(String.self, forKey: .routingState)
    self.responseGuidance = try container.decodeIfPresent(String.self, forKey: .responseGuidance)
    self.stopSignals = try container.decodeIfPresent([String].self, forKey: .stopSignals) ?? []
    self.failedAngles = try container.decodeIfPresent([String].self, forKey: .failedAngles) ?? []
    self.signalQuality =
      try container.decodeIfPresent(SignalQuality.self, forKey: .signalQuality) ?? .strong
    self.anglesCovered = try container.decodeIfPresent([String].self, forKey: .anglesCovered) ?? []
    self.evidenceTail = try container.decodeIfPresent([String].self, forKey: .evidenceTail) ?? []
    self.summarizedMessageCount = try container.decodeIfPresent(Int.self, forKey: .summarizedMessageCount) ?? 0
    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    self.totalMessageCount = try container.decodeIfPresent(Int.self, forKey: .totalMessageCount) ?? 0
  }

  nonisolated func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(coreEntryText, forKey: .coreEntryText)
    try container.encode(coreInsight, forKey: .coreInsight)
    try container.encodeIfPresent(nextOpenings, forKey: .nextOpenings)
    try container.encodeIfPresent(routingState, forKey: .routingState)
    try container.encodeIfPresent(responseGuidance, forKey: .responseGuidance)
    try container.encode(stopSignals, forKey: .stopSignals)
    try container.encode(failedAngles, forKey: .failedAngles)
    try container.encode(signalQuality, forKey: .signalQuality)
    try container.encode(anglesCovered, forKey: .anglesCovered)
    try container.encode(evidenceTail, forKey: .evidenceTail)
    try container.encode(summarizedMessageCount, forKey: .summarizedMessageCount)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(totalMessageCount, forKey: .totalMessageCount)
  }

  private enum CodingKeys: String, CodingKey {
    case coreEntryText
    case coreInsight
    case nextOpenings
    case routingState
    case responseGuidance
    case stopSignals
    case failedAngles
    case signalQuality
    case anglesCovered
    case evidenceTail
    case summarizedMessageCount
    case createdAt
    case totalMessageCount
  }
}

import Foundation
import os
import SwiftData
import Synchronization

// MARK: - AI Service Protocol

protocol AIService: AnyObject, Sendable {
  /// Generate a thought-provoking question for GoDeeper conversation with streaming
  /// - Parameters:
  ///   - entryText: The journal entry text
  ///   - conversationHistory: Previous conversation messages
  ///   - currentSummary: Optional existing conversation summary
  ///   - onChunk: Callback for streamed text chunks
  ///   - onSummaryCreated: Optional callback when a new summary is generated
  /// - Returns: Optional new summary if one was created during this call
  @discardableResult
  nonisolated func generateGoDeeperResponseStream(
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary?,
    onChunk: @escaping (String) -> Void,
    onSummaryCreated: ((ConversationSummary) -> Void)?
  ) async throws -> ConversationSummary?

}

extension AIService {
  /// Lensed variant of `generateGoDeeperResponseStream` that lets callers pass
  /// a one-line `seedLensHint` (e.g. "User started this entry from the prompt:
  /// 'what's still circling?'"). The hint biases the AI's first 1-2 questions
  /// without overriding the two-step Why-then-What method.
  ///
  /// The default implementation ignores the hint and forwards to the
  /// non-lensed call so existing mocks/test doubles keep working without
  /// having to override this overload.
  @discardableResult
  nonisolated func generateGoDeeperResponseStream(
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary?,
    seedLensHint: String?,
    onChunk: @escaping (String) -> Void,
    onSummaryCreated: ((ConversationSummary) -> Void)?
  ) async throws -> ConversationSummary? {
    _ = seedLensHint  // default impl: no-op
    return try await generateGoDeeperResponseStream(
      entryText: entryText,
      conversationHistory: conversationHistory,
      currentSummary: currentSummary,
      onChunk: onChunk,
      onSummaryCreated: onSummaryCreated
    )
  }

  @discardableResult
  nonisolated func generateGoDeeperResponseStream(
    entryId: String,
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary?,
    seedLensHint: String?,
    onChunk: @escaping (String) -> Void,
    onSummaryCreated: ((ConversationSummary) -> Void)?
  ) async throws -> ConversationSummary? {
    if let defaultService = self as? DefaultAIService {
      return try await defaultService.generateGoDeeperResponseStream(
        entryId: entryId,
        entryText: entryText,
        conversationHistory: conversationHistory,
        currentSummary: currentSummary,
        seedLensHint: seedLensHint,
        onChunk: onChunk,
        onSummaryCreated: onSummaryCreated
      )
    }

    _ = entryId
    return try await generateGoDeeperResponseStream(
      entryText: entryText,
      conversationHistory: conversationHistory,
      currentSummary: currentSummary,
      seedLensHint: seedLensHint,
      onChunk: onChunk,
      onSummaryCreated: onSummaryCreated
    )
  }
}

// MARK: - Default AI Service Implementation

final class DefaultAIService: Sendable, AIService {
  static let shared = DefaultAIService()

  struct LatencyConfig: Sendable {
    let minimumThinkTime: TimeInterval
    let ttftTimeout: TimeInterval

    static let production = LatencyConfig(
      minimumThinkTime: 1.8,
      ttftTimeout: 5.0
    )
  }

  private let backendClient: BackendAIClient
  private let _summaryTask = Mutex<Task<Void, Never>?>(nil)
  private let latencyConfig: LatencyConfig

  init(
    backendClient: BackendAIClient = BackendAIClient(),
    latencyConfig: LatencyConfig = .production
  ) {
    self.backendClient = backendClient
    self.latencyConfig = latencyConfig
  }

  private func validatedResponse(
    _ response: String,
    targetLanguage: (code: String, name: String)
  ) async throws -> String {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    let primaryVerdict = AILanguageValidator.validateResponse(
      trimmed,
      targetLanguageCode: targetLanguage.code
    )

    switch primaryVerdict {
    case .accept, .uncertain:
      return trimmed
    case .reject:
      AppLogger.ai.warning("Language validation rejected primary response; attempting repair")

      let repaired = try await backendClient.repairLanguage(
        originalResponse: trimmed,
        languageName: targetLanguage.name
      )

      guard !repaired.isEmpty else {
        throw AIServiceError.processingError("Language repair returned an empty response")
      }

      let repairedVerdict = AILanguageValidator.validateResponse(
        repaired,
        targetLanguageCode: targetLanguage.code
      )

      switch repairedVerdict {
      case .accept, .uncertain:
        AppLogger.ai.info("Language repair succeeded")
        return repaired
      case .reject:
        AppLogger.ai.error("Language repair failed validation twice")
        throw AIServiceError.languageValidationFailed
      }
    }
  }

  /// Warm up the AI service by initializing the client in advance
  /// Call this at app launch to avoid delays when first using AI features
  func warmUp() async {
    AppLogger.ai.info("Warming up DefaultAIService...")
    _ = backendClient
  }

  nonisolated func generateInsights(
    entryText: String,
    messages: [DialogueMessage]
  ) async throws -> ConversationInsights {
    try await backendClient.generateInsights(entryText: entryText, messages: messages)
  }

  // MARK: - GoDeeper Implementation

  @discardableResult
  nonisolated func generateGoDeeperResponseStream(
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary? = nil,
    onChunk: @escaping (String) -> Void,
    onSummaryCreated: ((ConversationSummary) -> Void)? = nil
  ) async throws -> ConversationSummary? {
    try await generateGoDeeperResponseStream(
      entryId: UUID().uuidString,
      entryText: entryText,
      conversationHistory: conversationHistory,
      currentSummary: currentSummary,
      seedLensHint: nil,
      onChunk: onChunk,
      onSummaryCreated: onSummaryCreated
    )
  }

  @discardableResult
  nonisolated func generateGoDeeperResponseStream(
    entryId: String,
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary? = nil,
    seedLensHint: String?,
    onChunk: @escaping (String) -> Void,
    onSummaryCreated: ((ConversationSummary) -> Void)? = nil
  ) async throws -> ConversationSummary? {
    guard !entryText.isEmpty else {
      throw AIServiceError.noData
    }

    let targetLanguage = LanguageDetector.uiLanguage()
    let requestStart = CFAbsoluteTimeGetCurrent()
    var latestResponse = ""
    _ = try await backendClient.generateGoDeeperResponseStream(
      entryId: entryId,
      entryText: entryText,
      conversationHistory: conversationHistory,
      currentSummary: currentSummary,
      seedLensHint: seedLensHint,
      onChunk: { chunk in
        latestResponse = chunk
        onChunk(chunk)
      }
    )

    let elapsed = CFAbsoluteTimeGetCurrent() - requestStart
    if elapsed < latencyConfig.minimumThinkTime {
      try await Task.sleep(for: .seconds(latencyConfig.minimumThinkTime - elapsed))
    }

    let fullResponse = try await validatedResponse(latestResponse, targetLanguage: targetLanguage)
    guard !fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AIServiceError.processingError("Empty response from AI")
    }
    if fullResponse != latestResponse {
      onChunk(fullResponse)
    }

    let wordCount = fullResponse.split(separator: " ").count
    if wordCount > 140 {
      AppLogger.ai.warning("AI response is unusually long for reflection engine: \(wordCount) words")
    }
    if fullResponse.contains("```") || fullResponse.contains("##") || fullResponse.contains("**") {
      AppLogger.ai.warning("AI response contains unexpected formatting")
    }

    // AFTER response: trigger background summarisation if needed.
    // Does not delay the streamed response.
    let shouldSummarize = shouldCreateSummary(
      conversationHistory: conversationHistory,
      currentSummary: currentSummary
    )

    if shouldSummarize {
      // Cancel any in-flight summary to prevent stale results from overwriting
      _summaryTask.withLock { $0?.cancel() }

      let task = Task.detached(priority: .utility) { [weak self] in
        guard let self = self else { return }

        AppLogger.ai.info("Starting background summarisation...")

        let completedMessages = conversationHistory.filter { !$0.content.isEmpty }
        let messageCount = completedMessages.count
        guard messageCount > 10 else { return }

        let alreadySummarized = currentSummary?.summarizedMessageCount ?? 0

        // End of the last completed 10-message block
        let windowEnd = ((messageCount - 1) / 10) * 10

        // O(n) fix: pass only NEW messages since the last summary.
        // Backend summarization builds on previousSummary for older context.
        let newMessages = Array(completedMessages[alreadySummarized..<windowEnd])
        guard !newMessages.isEmpty else { return }

        // Cooperative cancellation: bail out if a newer request already replaced us
        guard !Task.isCancelled else { return }

        do {
          let newSummary = try await self.backendClient.summarizeConversation(
            coreEntryText: entryText,
            newMessages: newMessages,
            previousSummary: currentSummary,
            totalSummarizedCount: windowEnd,
            totalMessageCount: conversationHistory.count
          )

          // Check cancellation again after the async work completes
          guard !Task.isCancelled else { return }

          await MainActor.run {
            onSummaryCreated?(newSummary)
          }

          AppLogger.ai.info("Summary updated: msgs \(alreadySummarized)…\(windowEnd) integrated")
        } catch {
          AppLogger.ai.warning("Background summarisation failed: \(error.localizedDescription)")
        }
      }

      _summaryTask.withLock { $0 = task }
    }

    return currentSummary
  }

  // MARK: - Summarisation Helpers

  /// Triggers every 10 completed messages (at 11, 21, 31…).
  /// Keeps a minimum live window of 10 raw messages between events for local coherence.
  private nonisolated func shouldCreateSummary(
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary?
  ) -> Bool {
    let completedMessageCount = conversationHistory.filter { !$0.content.isEmpty }.count
    return completedMessageCount > 1 && (completedMessageCount % 10 == 1)
  }
}

// MARK: - AI Service Errors

enum AIServiceError: LocalizedError {
  case noData
  case noActiveEntries
  case invalidJSON
  case processingError(String)
  case languageValidationFailed
  case conversationTooLong
  case emptyConversation
  /// First token not received within the TTFT deadline (all retry/fallback attempts exhausted).
  case ttftTimeout

  var errorDescription: String? {
    switch self {
    case .noData:
      return "No data available for analysis"
    case .noActiveEntries:
      return "No active entries found"
    case .invalidJSON:
      return "Failed to parse AI response"
    case .processingError(let message):
      return "Processing error: \(message)"
    case .languageValidationFailed:
      return "AI response did not match the selected app language"
    case .conversationTooLong:
      return "The conversation has become too long. Please start a new entry to continue."
    case .emptyConversation:
      return "Cannot continue conversation without an initial entry"
    case .ttftTimeout:
      return "The AI service is responding slowly. Please try again."
    }
  }
}

// MARK: - Mock AI Service (for testing/development)

final class MockAIService: @unchecked Sendable, AIService {
  @discardableResult
  nonisolated func generateGoDeeperResponseStream(
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary? = nil,
    onChunk: @escaping (String) -> Void,
    onSummaryCreated: ((ConversationSummary) -> Void)? = nil
  ) async throws -> ConversationSummary? {
    guard !entryText.isEmpty else {
      throw AIServiceError.noData
    }

    let response: String
    if conversationHistory.isEmpty {
      response =
        "Something in this moment seems to be asking for your attention.\nWhat feels most active right now?"
    } else if conversationHistory.count < 3 {
      response = "There is a thread here, but it is still forming.\nWhat changed when you first noticed it?"
    } else {
      response =
        "The same pattern keeps coming back around this.\nWhat does it seem to be asking for?"
    }

    try await Task.sleep(nanoseconds: 200_000_000)
    onChunk(response)

    return currentSummary  // Mock: return existing summary unchanged
  }

}

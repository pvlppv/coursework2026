import Foundation
import Testing

@testable import Sotie

@Suite(.serialized)
@MainActor
struct SotieTests {

  private func withAppLanguage<T>(
    _ languageCode: String,
    run operation: () async throws -> T
  ) async rethrows -> T {
    let previousLanguage = UserDefaults.standard.string(forKey: LanguageManager.appLanguageKey)
    UserDefaults.standard.set(languageCode, forKey: LanguageManager.appLanguageKey)
    defer {
      if let previousLanguage {
        UserDefaults.standard.set(previousLanguage, forKey: LanguageManager.appLanguageKey)
      } else {
        UserDefaults.standard.removeObject(forKey: LanguageManager.appLanguageKey)
      }
    }
    return try await operation()
  }

  @Test func userFacingAIErrorTreatsTrueOfflineAsNetwork() throws {
    let result = userFacingAIError(from: URLError(.notConnectedToInternet))

  #expect(result.message == appLocalizedString(Localizable.errorNetwork))
    #expect(result.retryAfter == nil)
  }

  @Test func userFacingAIErrorDoesNotTreatTTFTTimeoutAsNetwork() throws {
    let result = userFacingAIError(from: AIServiceError.ttftTimeout)

  #expect(result.message == appLocalizedString(Localizable.errorAIService))
    #expect(result.retryAfter == nil)
  }

  @Test func userFacingAIErrorDoesNotTreatProviderFailureAsNetwork() throws {
    let result = userFacingAIError(from: OpenAIClientError.apiError("provider unavailable", 503))

  #expect(result.message == appLocalizedString(Localizable.errorAIService))
    #expect(result.retryAfter == nil)
  }

  @Test func userFacingAIErrorDoesNotTreatInvalidAPIKeyAsNetwork() throws {
    let result = userFacingAIError(from: OpenAIClientError.invalidAPIKey)

  #expect(result.message == appLocalizedString(Localizable.errorAIService))
    #expect(result.retryAfter == nil)
  }

  @Test func userFacingAIErrorKeepsRateLimitCooldown() throws {
    let result = userFacingAIError(from: OpenAIClientError.localRateLimitExceeded(retryAfter: 7.2))

  #expect(result.message == appLocalizedString(Localizable.errorRateLimited, arguments: 8))
    #expect(result.retryAfter == 7.2)
  }

  @Test func streamingParserExtractsContentChunks() throws {
    let event = OpenAIStreamingEventParser.parse(
      "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"
    )

    guard case .content(let content) = event else {
      Issue.record("Expected content event, got \(String(describing: event))")
      return
    }

    #expect(content == "Hello")
  }

  @Test func streamingParserDetectsErrorPayloads() throws {
    let event = OpenAIStreamingEventParser.parse(
      "data: {\"error\":{\"message\":\"provider overloaded\",\"code\":503}}"
    )

    guard case .failure(let error) = event else {
      Issue.record("Expected failure event, got \(String(describing: event))")
      return
    }

    guard case .apiError(let message, let code) = error else {
      Issue.record("Expected apiError, got \(String(describing: error))")
      return
    }

    #expect(message == "provider overloaded")
    #expect(code == 503)
  }

  @Test func streamingParserRecognizesDoneSentinel() throws {
    let event = OpenAIStreamingEventParser.parse("data: [DONE]")

    guard case .done = event else {
      Issue.record("Expected done event, got \(String(describing: event))")
      return
    }
  }

  @Test func engineTreatsTTFTTimeoutAsGenericAIServiceFailure() async throws {
    await resetPremiumStateForEngineTests()

    let engine = GoDeeperEngine(
      entryId: UUID().uuidString,
      aiService: ErrorThrowingAIService(error: AIServiceError.ttftTimeout)
    )
    engine.observationText = "I feel stuck."

    engine.startGoDeeper()

    await waitForEngineToSettle(engine)

  #expect(engine.aiErrorMessage == appLocalizedString(Localizable.errorAIService))
    #expect(engine.errorRetryAvailableAt == nil)
  }

  @Test func engineTreatsTrueOfflineAsNetworkFailure() async throws {
    await resetPremiumStateForEngineTests()

    let engine = GoDeeperEngine(
      entryId: UUID().uuidString,
      aiService: ErrorThrowingAIService(error: OpenAIClientError.networkError(URLError(.notConnectedToInternet)))
    )
    engine.observationText = "I feel stuck."

    engine.startGoDeeper()

    await waitForEngineToSettle(engine)

  #expect(engine.aiErrorMessage == appLocalizedString(Localizable.errorNetwork))
    #expect(engine.errorRetryAvailableAt == nil)
  }

  @Test func engineTreatsProviderFailureAsGenericAIServiceFailure() async throws {
    await resetPremiumStateForEngineTests()

    let engine = GoDeeperEngine(
      entryId: UUID().uuidString,
      aiService: ErrorThrowingAIService(error: OpenAIClientError.apiError("provider unavailable", 503))
    )
    engine.observationText = "I feel stuck."

    engine.startGoDeeper()

    await waitForEngineToSettle(engine)

  #expect(engine.aiErrorMessage == appLocalizedString(Localizable.errorAIService))
    #expect(engine.errorRetryAvailableAt == nil)
  }

  @Test func regeneratingLastQuestionKeepsPreviousAssistantMessageVisibleUntilReplacementArrives()
    async throws
  {
    await resetPremiumStateForEngineTests()

    let replacementQuestion = "What are you protecting by staying in this loop?"
    let aiService = BlockingAIService(response: replacementQuestion)

    let userMessage = DialogueMessage(role: .user, content: "I keep replaying the same thought.")
    let assistantMessage = DialogueMessage(
      role: .assistant,
      content: "What feels unfinished about it?"
    )

    let engine = GoDeeperEngine(
      entryId: UUID().uuidString,
      aiService: aiService,
      initialMessages: [userMessage, assistantMessage],
      initialOriginalEntryText: userMessage.content
    )

    engine.sendMessageAndContinue(focusedMessageId: userMessage.id)
    await aiService.waitUntilStarted()

    #expect(engine.isGeneratingAI)
    #expect(engine.conversationMessages.count == 2)
    #expect(engine.conversationMessages.last?.id == assistantMessage.id)
    #expect(engine.conversationMessages.last?.content.isEmpty == true)

    aiService.release()

    await waitForEngineToSettle(engine)

    #expect(engine.conversationMessages.count == 2)
    #expect(engine.conversationMessages.last?.id == assistantMessage.id)
    #expect(engine.conversationMessages.last?.content == replacementQuestion)
  }

  @Test func cancellingInPlaceRegenerationRestoresPreviousAssistantMessage() async throws {
    await resetPremiumStateForEngineTests()

    let aiService = BlockingAIService(response: "Replacement question?")
    let userMessage = DialogueMessage(role: .user, content: "I keep replaying the same thought.")
    let assistantMessage = DialogueMessage(
      role: .assistant,
      content: "What feels unfinished about it?"
    )

    let engine = GoDeeperEngine(
      entryId: UUID().uuidString,
      aiService: aiService,
      initialMessages: [userMessage, assistantMessage],
      initialOriginalEntryText: userMessage.content
    )

    engine.sendMessageAndContinue(focusedMessageId: userMessage.id)
    await aiService.waitUntilStarted()

    #expect(engine.conversationMessages.last?.content.isEmpty == true)

    engine.cancelStreaming()

    #expect(engine.isGeneratingAI == false)
    #expect(engine.conversationMessages.count == 2)
    #expect(engine.conversationMessages.last?.id == assistantMessage.id)
    #expect(engine.conversationMessages.last?.content == assistantMessage.content)
  }

  @Test func failedInPlaceRegenerationRestoresPreviousAssistantMessage() async throws {
    await resetPremiumStateForEngineTests()

    let aiService = FailingAIService()
    let userMessage = DialogueMessage(role: .user, content: "I keep replaying the same thought.")
    let assistantMessage = DialogueMessage(
      role: .assistant,
      content: "What feels unfinished about it?"
    )

    let engine = GoDeeperEngine(
      entryId: UUID().uuidString,
      aiService: aiService,
      initialMessages: [userMessage, assistantMessage],
      initialOriginalEntryText: userMessage.content
    )

    engine.sendMessageAndContinue(focusedMessageId: userMessage.id)

    await waitForEngineToSettle(engine)

    #expect(engine.conversationMessages.count == 2)
    #expect(engine.conversationMessages.last?.id == assistantMessage.id)
    #expect(engine.conversationMessages.last?.content == assistantMessage.content)
    #expect(engine.aiErrorMessage?.isEmpty == false)
  }

  @Test func retryAfterFailedInPlaceRegenerationReusesCorrectAssistantBubble() async throws {
    await resetPremiumStateForEngineTests()

    let replacementQuestion = "What would change if you stopped replaying it?"

    let aiService = FailThenSucceedAIService(
      firstError: URLError(.badServerResponse),
      successResponse: replacementQuestion
    )
    let userMessage = DialogueMessage(role: .user, content: "I keep replaying the same thought.")
    let assistantMessage = DialogueMessage(
      role: .assistant,
      content: "What feels unfinished about it?"
    )

    let engine = GoDeeperEngine(
      entryId: UUID().uuidString,
      aiService: aiService,
      initialMessages: [userMessage, assistantMessage],
      initialOriginalEntryText: userMessage.content
    )

    // Trigger in-place regen → fails → restores snapshot
    engine.sendMessageAndContinue(focusedMessageId: userMessage.id)

    await waitForEngineToSettle(engine)

    // After failure: old response restored, error shown
    #expect(engine.conversationMessages.count == 2)
    #expect(engine.conversationMessages.last?.content == assistantMessage.content)
    #expect(engine.aiErrorMessage != nil)

    engine.retryLastGeneration()

    await waitForEngineToSettle(engine)

    // Should have exactly 2 messages, not 3
    #expect(engine.conversationMessages.count == 2)
    #expect(engine.conversationMessages.last?.id == assistantMessage.id)
    #expect(engine.conversationMessages.last?.content == replacementQuestion)
    #expect(engine.aiErrorMessage == nil)
  }

  @Test func regeneratingFromMiddleUserMessageRebranchesConversationFromThatPoint() async throws {
    await resetPremiumStateForEngineTests()

    let aiService = ImmediateAIService(response: "What changes if you stop protecting that?")
    let firstUser = DialogueMessage(role: .user, content: "First thought")
    let firstAssistant = DialogueMessage(role: .assistant, content: "First question?")
    let middleUser = DialogueMessage(role: .user, content: "Second thought")
    let middleAssistant = DialogueMessage(role: .assistant, content: "Second question?")
    let lastUser = DialogueMessage(role: .user, content: "Third thought")
    let lastAssistant = DialogueMessage(role: .assistant, content: "Third question?")

    let engine = GoDeeperEngine(
      entryId: UUID().uuidString,
      aiService: aiService,
      initialMessages: [firstUser, firstAssistant, middleUser, middleAssistant, lastUser, lastAssistant],
      initialOriginalEntryText: firstUser.content
    )

    engine.sendMessageAndContinue(focusedMessageId: middleUser.id)

    await waitForEngineToSettle(engine)

    let messages = engine.conversationMessages
    #expect(messages.count == 4)
    #expect(messages.first?.id == firstUser.id)
    #expect(messages.dropFirst().first?.id == firstAssistant.id)
    #expect(messages.dropFirst(2).first?.id == middleUser.id)
    #expect(messages.last?.role == .assistant)
    #expect(messages.last?.content == "What changes if you stop protecting that?")
  }

  @Test func regeneratingFromFirstUserMessageRebranchesFromConversationStart() async throws {
    await resetPremiumStateForEngineTests()

    let aiService = ImmediateAIService(response: "What matters most in this first moment?")
    let firstUser = DialogueMessage(role: .user, content: "First thought")
    let firstAssistant = DialogueMessage(role: .assistant, content: "First question?")
    let secondUser = DialogueMessage(role: .user, content: "Second thought")
    let secondAssistant = DialogueMessage(role: .assistant, content: "Second question?")

    let engine = GoDeeperEngine(
      entryId: UUID().uuidString,
      aiService: aiService,
      initialMessages: [firstUser, firstAssistant, secondUser, secondAssistant],
      initialOriginalEntryText: firstUser.content
    )

    engine.sendMessageAndContinue(focusedMessageId: firstUser.id)

    await waitForEngineToSettle(engine)

    let messages = engine.conversationMessages
    #expect(messages.count == 2)
    #expect(messages.first?.id == firstUser.id)
    #expect(messages.dropFirst().first?.role == .assistant)
    #expect(messages.dropFirst().first?.content == "What matters most in this first moment?")
  }

}

@MainActor
private func resetPremiumStateForEngineTests() async {
  PremiumManager.shared.resetAllData()
  await PremiumManager.shared.loadSubscriptionStatus()
  PremiumManager.shared.resetOnboardingAIDemo()
}

@MainActor
private func waitForEngineToSettle(_ engine: GoDeeperEngine) async {
  while engine.isGeneratingAI {
    await Task.yield()
  }

  for _ in 0..<20 {
    await Task.yield()
  }
}

private final class BlockingAIService: @unchecked Sendable, AIService {
  private let response: String
  private let lock = NSLock()
  private var didStart = false
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  init(response: String) {
    self.response = response
  }

  func waitUntilStarted() async {
    while true {
      let started = lock.withLock { didStart }
      if started { return }
      await Task.yield()
    }
  }

  func release() {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      let continuation = releaseContinuation
      releaseContinuation = nil
      return continuation
    }
    continuation?.resume()
  }

  @discardableResult
  func generateGoDeeperResponseStream(
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary?,
    onChunk: @escaping (String) -> Void,
    onSummaryCreated: ((ConversationSummary) -> Void)?
  ) async throws -> ConversationSummary? {
    lock.withLock {
      didStart = true
    }

    await withCheckedContinuation { continuation in
      lock.withLock {
        releaseContinuation = continuation
      }
    }

    onChunk(response)
    return currentSummary
  }
}

private final class FailingAIService: @unchecked Sendable, AIService {
  @discardableResult
  func generateGoDeeperResponseStream(
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary?,
    onChunk: @escaping (String) -> Void,
    onSummaryCreated: ((ConversationSummary) -> Void)?
  ) async throws -> ConversationSummary? {
    throw URLError(.badServerResponse)
  }
}

private final class ImmediateAIService: @unchecked Sendable, AIService {
  private let response: String

  init(response: String) {
    self.response = response
  }

  @discardableResult
  func generateGoDeeperResponseStream(
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary?,
    onChunk: @escaping (String) -> Void,
    onSummaryCreated: ((ConversationSummary) -> Void)?
  ) async throws -> ConversationSummary? {
    onChunk(response)
    return currentSummary
  }
}

private final class ErrorThrowingAIService: @unchecked Sendable, AIService {
  private let error: Error

  init(error: Error) {
    self.error = error
  }

  @discardableResult
  func generateGoDeeperResponseStream(
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary?,
    onChunk: @escaping (String) -> Void,
    onSummaryCreated: ((ConversationSummary) -> Void)?
  ) async throws -> ConversationSummary? {
    throw error
  }
}

private final class FailThenSucceedAIService: @unchecked Sendable, AIService {
  private let lock = NSLock()
  private var didFailOnce = false
  private let firstError: Error
  private let successResponse: String

  init(firstError: Error, successResponse: String) {
    self.firstError = firstError
    self.successResponse = successResponse
  }

  @discardableResult
  func generateGoDeeperResponseStream(
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary?,
    onChunk: @escaping (String) -> Void,
    onSummaryCreated: ((ConversationSummary) -> Void)?
  ) async throws -> ConversationSummary? {
    let shouldFail = lock.withLock { () -> Bool in
      if didFailOnce { return false }
      didFailOnce = true
      return true
    }

    if shouldFail {
      throw firstError
    }

    onChunk(successResponse)
    return currentSummary
  }
}

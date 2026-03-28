import Foundation
import os
import SwiftUI

/// Shared engine for the "Go Deeper" AI conversation flow.
///
/// Both `AddEntryViewModel` and `EditEntryViewModel` delegate all
/// conversation logic to this class, eliminating ~160 LOC of duplication and
/// ensuring a single source of truth for streaming, quota checks, rollback,
/// and analytics tracking.
@Observable
@MainActor
final class GoDeeperEngine {

  // MARK: - Public State (observed by Views through ViewModel proxies)

  var conversationMessages: [DialogueMessage] = []
  var conversationSummary: ConversationSummary?
  var isGeneratingAI = false
  var aiErrorMessage: String?
  /// When rate-limit cooldown expires. nil = no cooldown active.
  var errorRetryAvailableAt: Date?
  /// True when the last error was a response-limit paywall error.
  private(set) var isAIResponseLimitError: Bool = false

  /// Tracked AI request task for cancellation on new request / view disappear.
  private(set) var currentRequestTask: Task<Void, Never>?

  /// True while the local rate-limit cooldown is still ticking.
  var isRateLimitCoolingDown: Bool {
    guard let retryDate = errorRetryAvailableAt else { return false }
    return Date() < retryDate
  }

  // MARK: - Private State

  /// Canonical original entry text — captured once at startGoDeeper().
  /// Used as the single source of truth for AI prompt anchor.
  private(set) var cachedOriginalEntryText: String?

  /// Entry/session identifier for quota tracking.
  /// - For new entries: a fresh UUID string (sessionId)
  /// - For existing entries: entry.id.uuidString
  private let entryId: String

  /// Snapshot of the visible conversation before an in-place regeneration.
  /// Used to restore the previous response if the refresh is cancelled or fails.
  /// Only stores `conversationMessages`; `observationText` is NOT modified during
  /// in-place regen, so there's nothing to roll back.
  private var inPlaceRegenerationSnapshot: [DialogueMessage]?

  /// Optional cluster + sub-state metadata captured when a user seeds an
  /// entry from a prompt card. Persists for the entire session and is
  /// converted to the AI seed-lens hint at request time. Cleared by
  /// `clearPromptSeed()` and `reset()`.
  private(set) var promptSeed: PromptSeed?

  /// Lightweight metadata describing how the user seeded this entry.
  ///
  /// `cluster` is what the user tapped on the rail; `subState` is the
  /// specific sub-state the opener picker rolled from the cluster's union
  /// pool (drives icon variety on the selected card and the second line of
  /// the lens hint).
  struct PromptSeed: Sendable, Equatable {
    let cluster: PromptCluster
    let subState: PromptCategory
    let openerText: String
    let openerIndex: Int
  }

  /// Reference to the AI service (protocol-based for testability).
  private let aiService: AIService

  /// Reference to the text field — engine reads/writes it for rollback and clearing.
  /// VM sets this binding on init or startGoDeeper.
  var observationText: String = ""

  /// Context for retrying the last failed generation.
  /// Stored when a generation fails so `retryLastGeneration()` can replay it correctly.
  private var lastGenerationContext: GenerationContext?

  /// Captures everything needed to replay a generation attempt.
  private struct GenerationContext {
    let rollbackSnapshot: ([DialogueMessage], String)?
    let requestConversationHistory: [DialogueMessage]?
    let replacingAssistantMessageId: UUID?
    let trigger: Analytics.GoDeeperTrigger
  }

  // MARK: - Callbacks

  /// Called when the engine needs the VM to know conversation changed
  /// (e.g., for auto-save in EditEntryViewModel).
  var onConversationUpdated: (() -> Void)?

  /// Called when generateAIResponse rolls back observation text on error.
  /// The VM must update its own `observation` property in this closure.
  var onObservationRollback: ((String) -> Void)?

  // MARK: - Init

  init(
    entryId: String,
    aiService: AIService? = nil,
    initialMessages: [DialogueMessage] = [],
    initialSummary: ConversationSummary? = nil,
    initialOriginalEntryText: String? = nil
  ) {
    self.entryId = entryId
    self.aiService = aiService ?? DefaultAIService.shared
    self.conversationMessages = initialMessages
    self.conversationSummary = initialSummary
    self.cachedOriginalEntryText = initialOriginalEntryText
  }

  // MARK: - Public API

  /// Seed the conversation with a cluster-driven opener as the first
  /// assistant message. No AI call — the opener is verbatim from the
  /// catalog. Replaces any existing seed if the user hasn't sent a reply
  /// yet (state B → B). No-op once the user has committed a reply.
  ///
  /// Call sites: `AddEntryView` when a prompt card is tapped.
  ///
  /// - Parameters:
  ///   - cluster: which cluster the user tapped on the rail.
  ///   - subState: the specific sub-state the opener picker drew (drives
  ///     icon variety + second line of AI lens hint).
  ///   - openerText: localized opener text shown in the assistant bubble.
  ///   - openerIndex: 1-based index into the sub-state's opener pool.
  ///   - revealMode: `.streamingPlaceholder` inserts an empty bubble first
  ///     and waits for the caller to commit the reveal via
  ///     `commitSeedReveal(text:)`. `.immediate` writes the full text right
  ///     away (used for draft restoration, where the animation would feel
  ///     wrong on app relaunch).
  func seedWithPrompt(
    cluster: PromptCluster,
    subState: PromptCategory,
    openerText: String,
    openerIndex: Int,
    revealMode: SeedRevealMode = .immediate
  ) {
    let trimmedOpener = openerText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedOpener.isEmpty else { return }

    // If the user already sent a reply, the seed is locked.
    let hasUserReply = conversationMessages.contains { $0.role == .user }
    guard !hasUserReply else { return }

    promptSeed = PromptSeed(
      cluster: cluster,
      subState: subState,
      openerText: trimmedOpener,
      openerIndex: openerIndex
    )

    let bubbleContent: String
    switch revealMode {
    case .immediate: bubbleContent = trimmedOpener
    case .streamingPlaceholder: bubbleContent = ""
    }

    let seedMessage = DialogueMessage(role: .assistant, content: bubbleContent)
    if let existing = conversationMessages.first, existing.role == .assistant {
      conversationMessages[0] = seedMessage
    } else {
      conversationMessages.insert(seedMessage, at: 0)
    }

    // One soft selection tap per card press — fires from the engine so the
    // VM/View doesn't double-fire it. The heavier stream-end success haptic
    // is suppressed for synthetic reveals (see `playFinishHaptic` on
    // `AIMessageRow`).
    HapticManager.shared.selection()
  }

  /// Streaming-style reveal mode for `seedWithPrompt`.
  enum SeedRevealMode {
    /// Write the full opener text into the bubble immediately.
    case immediate
    /// Insert an empty assistant bubble first; caller must follow up with
    /// `commitSeedReveal(text:)` once the sparkle has had time to show.
    case streamingPlaceholder
  }

  /// Commit the deferred opener text from `seedWithPrompt(revealMode:.streamingPlaceholder)`.
  /// Sets the first assistant message's content, which triggers the
  /// `AIMessageRow` blur-reveal cascade exactly like a streamed AI response.
  /// No-op if there's no pending seed bubble.
  func commitSeedReveal(text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard let first = conversationMessages.first, first.role == .assistant else { return }
    conversationMessages[0].content = trimmed
  }

  /// Clear the prompt seed and remove the seeded assistant message.
  /// Safe to call at any time; no-op if no seed is active or if the user
  /// has already replied (locked).
  func clearPromptSeed() {
    guard promptSeed != nil else { return }
    let hasUserReply = conversationMessages.contains { $0.role == .user }
    guard !hasUserReply else { return }

    promptSeed = nil
    if let first = conversationMessages.first, first.role == .assistant {
      conversationMessages.removeFirst()
    }
  }

  /// Begin a new Go Deeper conversation from the current observation text.
  func startGoDeeper() {
    guard !observationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    // Snapshot BEFORE mutation for rollback on stream failure
    let conversationSnapshot = conversationMessages
    let observationSnapshot = observationText

    // Capture canonical original entry text (once, if not already set)
    if cachedOriginalEntryText == nil {
      cachedOriginalEntryText = observationText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Save the initial entry text as first user message
    let initialMessage = DialogueMessage(
      role: .user,
      content: observationText.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    conversationMessages.append(initialMessage)

    // Clear observation field for future responses
    observationText = ""

    let context = GenerationContext(
      rollbackSnapshot: (conversationSnapshot, observationSnapshot),
      requestConversationHistory: nil,
      replacingAssistantMessageId: nil,
      trigger: .start
    )

    Analytics.goDeeperRequested(
      responseNumber: nextResponseNumber(for: conversationMessages),
      trigger: context.trigger,
      hasSummary: conversationSummary != nil,
      conversationDepth: conversationMessages.count,
      isFirstAssistantMessage: !conversationMessages.contains { $0.role == .assistant }
    )

    currentRequestTask?.cancel()
    currentRequestTask = Task {
      await generateAIResponse(context: context)
    }
  }

  /// Send a user message and generate the next AI response.
  ///
  /// - Parameter focusedMessageId: If non-nil, re-branch from this message
  ///   (editing an earlier reply). Otherwise sends the current observation text.
  func sendMessageAndContinue(focusedMessageId: UUID?) {
    let assistantMessageToReplaceId: UUID?
    let requestConversationHistory: [DialogueMessage]

    // Create snapshot for rollback on error
    let conversationSnapshot = conversationMessages
    let observationSnapshot = observationText

    // If a message is focused, use its content; otherwise use observation
    if let messageId = focusedMessageId,
      let index = conversationMessages.firstIndex(where: { $0.id == messageId })
    {
      let isRefreshingLastAssistant =
        index == conversationMessages.count - 2
        && conversationMessages[index].role == .user
        && conversationMessages.last?.role == .assistant

      if isRefreshingLastAssistant {
        inPlaceRegenerationSnapshot = conversationSnapshot
        assistantMessageToReplaceId = conversationMessages.last?.id
        requestConversationHistory = Array(conversationMessages.dropLast())
        let trigger: Analytics.GoDeeperTrigger = .refreshLastAssistant

        // Only invalidate summary if it actually covered the assistant message
        // being regenerated (the last one). `summarizedMessageCount` counts from
        // the start, so it must reach past the last message to be stale.
        if let summary = conversationSummary,
          summary.summarizedMessageCount >= conversationMessages.count
        {
          conversationSummary = nil
        }

        let context = GenerationContext(
          rollbackSnapshot: (conversationSnapshot, observationSnapshot),
          requestConversationHistory: requestConversationHistory,
          replacingAssistantMessageId: assistantMessageToReplaceId,
          trigger: trigger
        )

        Analytics.goDeeperRequested(
          responseNumber: nextResponseNumber(for: conversationMessages),
          trigger: trigger,
          hasSummary: conversationSummary != nil,
          conversationDepth: requestConversationHistory.count,
          isFirstAssistantMessage: false
        )

        currentRequestTask?.cancel()
        currentRequestTask = Task {
          await generateAIResponse(context: context)
        }
        return
      } else {
        inPlaceRegenerationSnapshot = nil
        assistantMessageToReplaceId = nil

        // Remove all messages after the edited one
        conversationMessages = Array(conversationMessages.prefix(upTo: index + 1))
        requestConversationHistory = conversationMessages

        // Invalidate summary if it describes a now-removed conversation branch
        if let summary = conversationSummary,
          summary.summarizedMessageCount > conversationMessages.count
        {
          conversationSummary = nil
        }

        let context = GenerationContext(
          rollbackSnapshot: (conversationSnapshot, observationSnapshot),
          requestConversationHistory: requestConversationHistory,
          replacingAssistantMessageId: assistantMessageToReplaceId,
          trigger: .editRegenerate
        )

        Analytics.goDeeperRequested(
          responseNumber: nextResponseNumber(for: conversationMessages),
          trigger: .editRegenerate,
          hasSummary: conversationSummary != nil,
          conversationDepth: requestConversationHistory.count,
          isFirstAssistantMessage: false
        )

        currentRequestTask?.cancel()
        currentRequestTask = Task {
          await generateAIResponse(context: context)
        }
        return
      }
    } else {
      // Using new text from bottom editor
      let textToSend = observationText.trimmingCharacters(in: .whitespacesAndNewlines)
      inPlaceRegenerationSnapshot = nil
      assistantMessageToReplaceId = nil

      guard !textToSend.isEmpty else {
        return
      }

      // If this is the very first user message after a prompt seed, capture
      // it as the canonical original-entry anchor. Mirrors `startGoDeeper`'s
      // behavior so Go Deeper's drift-prevention has a real anchor to use.
      if cachedOriginalEntryText == nil {
        let isFirstUserMessage = !conversationMessages.contains { $0.role == .user }
        if isFirstUserMessage {
          cachedOriginalEntryText = textToSend
        }
      }

      // Add user's message to conversation
      let userMessage = DialogueMessage(
        role: .user,
        content: textToSend
      )
      conversationMessages.append(userMessage)

      // Track user response
      AnalyticsTracker.shared.recordUserResponse()

      // Clear observation field for next message
      observationText = ""
      requestConversationHistory = conversationMessages

      let context = GenerationContext(
        rollbackSnapshot: (conversationSnapshot, observationSnapshot),
        requestConversationHistory: requestConversationHistory,
        replacingAssistantMessageId: assistantMessageToReplaceId,
        trigger: .continue
      )

      Analytics.goDeeperRequested(
        responseNumber: nextResponseNumber(for: conversationMessages),
        trigger: .continue,
        hasSummary: conversationSummary != nil,
        conversationDepth: requestConversationHistory.count,
        isFirstAssistantMessage: false
      )

      currentRequestTask?.cancel()
      currentRequestTask = Task {
        await generateAIResponse(context: context)
      }
      return
    }

  }

  /// Clear the current AI error and rate limit cooldown.
  func clearAIError() {
    aiErrorMessage = nil
    errorRetryAvailableAt = nil
    isAIResponseLimitError = false
  }

  /// Retry the last failed AI generation.
  ///
  /// Uses the stored `lastGenerationContext` to correctly replay the last
  /// operation — including in-place regeneration with the right snapshot,
  /// conversation history, and replacement target.
  func retryLastGeneration() {
    clearAIError()

    // Re-enter the in-place path if the last operation was an in-place regen.
    // The snapshot was restored on failure, so we need to re-detect and re-set it.
    if let ctx = lastGenerationContext, ctx.replacingAssistantMessageId != nil {
      // The snapshot was already restored, so conversationMessages is back to the
      // pre-regen state. Re-snapshot and re-clear the assistant content.
      let snapshot = conversationMessages
      inPlaceRegenerationSnapshot = snapshot

      if let replaceId = ctx.replacingAssistantMessageId,
        let idx = conversationMessages.firstIndex(where: {
          $0.id == replaceId && $0.role == .assistant
        })
      {
        conversationMessages[idx].content = ""
      }

      let retryContext = GenerationContext(
        rollbackSnapshot: (snapshot, observationText),
        requestConversationHistory: ctx.requestConversationHistory,
        replacingAssistantMessageId: ctx.replacingAssistantMessageId,
        trigger: .retry
      )

      Analytics.goDeeperRequested(
        responseNumber: nextResponseNumber(for: conversationMessages),
        trigger: .retry,
        hasSummary: conversationSummary != nil,
        conversationDepth: (ctx.requestConversationHistory ?? conversationMessages).count,
        isFirstAssistantMessage: false
      )

      currentRequestTask?.cancel()
      currentRequestTask = Task {
        await generateAIResponse(context: retryContext)
      }
    } else {
      // Normal retry — no special context needed
      let context = lastGenerationContext ?? GenerationContext(
        rollbackSnapshot: nil,
        requestConversationHistory: nil,
        replacingAssistantMessageId: nil,
        trigger: .retry
      )

      Analytics.goDeeperRequested(
        responseNumber: nextResponseNumber(for: conversationMessages),
        trigger: .retry,
        hasSummary: conversationSummary != nil,
        conversationDepth: (context.requestConversationHistory ?? conversationMessages).count,
        isFirstAssistantMessage: false
      )

      currentRequestTask?.cancel()
      currentRequestTask = Task {
        await generateAIResponse(context: context)
      }
    }
  }

  /// Reset conversation state (used by AddEntryVM on discard).
  func reset() {
    conversationMessages = []
    conversationSummary = nil
    cachedOriginalEntryText = nil
    inPlaceRegenerationSnapshot = nil
    lastGenerationContext = nil
    promptSeed = nil
    isGeneratingAI = false
    aiErrorMessage = nil
    errorRetryAvailableAt = nil
    isAIResponseLimitError = false
    currentRequestTask?.cancel()
    currentRequestTask = nil
  }

  /// Gracefully cancel any in-flight AI streaming.
  /// Removes trailing empty assistant message stubs so save won't persist placeholders.
  /// Safe to call even when no streaming is active (no-op).
  func cancelStreaming() {
    guard isGeneratingAI else { return }

    currentRequestTask?.cancel()
    currentRequestTask = nil

    if restoreInPlaceSnapshotIfNeeded() {
      // Snapshot restored — old response is back in place
    } else if let lastMessage = conversationMessages.last,
      lastMessage.role == .assistant,
      lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      // Remove trailing empty assistant message (the streaming placeholder)
      conversationMessages.removeLast()
    }

    isGeneratingAI = false
  }

  /// Set the canonical original entry text (used by EditEntryVM for existing entries).
  func setCachedOriginalEntryText(_ text: String?) {
    cachedOriginalEntryText = text
  }

  // MARK: - Snapshot Restore Helper

  /// Restores the conversation from the in-place regeneration snapshot, if one exists.
  /// Returns `true` if a snapshot was restored.
  @discardableResult
  private func restoreInPlaceSnapshotIfNeeded() -> Bool {
    guard let snapshot = inPlaceRegenerationSnapshot else { return false }
    conversationMessages = snapshot
    inPlaceRegenerationSnapshot = nil
    return true
  }

  private func nextResponseNumber(for messages: [DialogueMessage]) -> Int {
    messages.filter { $0.role == .assistant }.count + 1
  }

  private func normalizedAnalyticsReason(for error: Error) -> String {
    switch error {
    case is AIServiceError:
      if let aiError = error as? AIServiceError {
        switch aiError {
        case .ttftTimeout:
          return "ttft_timeout"
        case .emptyConversation:
          return "empty_conversation"
        case .languageValidationFailed:
          return "language_validation_failed"
        case .processingError:
          return "processing_error"
        default:
          return "ai_service_error"
        }
      }
    case is OpenAIClientError:
      if let clientError = error as? OpenAIClientError {
        switch clientError {
        case .rateLimitExceeded:
          return "rate_limit"
        case .localRateLimitExceeded:
          return "local_rate_limit"
        case .networkError(let underlyingError):
          if let urlError = underlyingError as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .dataNotAllowed:
              return "network_offline"
            case .networkConnectionLost:
              return "network_connection_lost"
            case .timedOut:
              return "url_timeout"
            default:
              return "network_error"
            }
          }
          return "network_error"
        case .apiError(_, let code) where (500...599).contains(code):
          return "server_error"
        case .invalidAPIKey:
          return "invalid_api_key"
        default:
          return "openai_client_error"
        }
      }
    default:
      break
    }

    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet, .dataNotAllowed:
        return "network_offline"
      case .networkConnectionLost:
        return "network_connection_lost"
      case .timedOut:
        return "url_timeout"
      default:
        return "url_error"
      }
    }

    return "unknown"
  }

  private func isRetryableAnalyticsError(_ error: Error) -> Bool {
    switch error {
    case let clientError as OpenAIClientError:
      switch clientError {
      case .rateLimitExceeded, .localRateLimitExceeded, .networkError, .apiError:
        return true
      default:
        return false
      }
    case let urlError as URLError:
      switch urlError.code {
      case .networkConnectionLost, .timedOut:
        return true
      default:
        return false
      }
    case AIServiceError.ttftTimeout:
      return true
    default:
      return false
    }
  }

  // MARK: - Core Generation Logic (single source of truth)

  @MainActor
  private func generateAIResponse(context: GenerationContext) async {

    // Store context for potential retry
    lastGenerationContext = context

    isGeneratingAI = true
    aiErrorMessage = nil
    isAIResponseLimitError = false

    let rollbackSnapshot = context.rollbackSnapshot
    let requestConversationHistory = context.requestConversationHistory
    let replacingAssistantMessageId = context.replacingAssistantMessageId

    do {
      // Check premium response limit BEFORE generating
      guard await AIQuotaManager.shared.canRequestAIResponse(forEntryId: entryId) else {
        isAIResponseLimitError = true
        aiErrorMessage = PremiumError.responseLimitReached.localizedDescription
        isGeneratingAI = false
        Analytics.freeAIBlocked()
        Analytics.aiError(
          reason: "response_limit_reached",
          stage: .quotaCheck,
          trigger: context.trigger,
          responseNumber: nextResponseNumber(for: conversationMessages),
          isRetryable: false
        )
        // NOTE: intentionally NO rollback here.
        // The user message must stay in conversationMessages so that
        // retryLastGeneration() (after purchase) generates an AI response
        // to it — otherwise we'd get two consecutive AI messages with no
        // user reply in between.
        return
      }

      // Get the original entry text — canonical source of truth
      let entryText = cachedOriginalEntryText
        ?? conversationMessages.first(where: { $0.role == .user })?.content
        ?? observationText.trimmingCharacters(in: .whitespacesAndNewlines)
      let conversationHistoryForRequest = requestConversationHistory ?? conversationMessages

      // Validate entry text is not empty
      guard !entryText.isEmpty else {
        aiErrorMessage = AIServiceError.emptyConversation.localizedDescription
        isGeneratingAI = false
        if let (conversationSnapshot, observationSnapshot) = rollbackSnapshot {
          conversationMessages = conversationSnapshot
          observationText = observationSnapshot
        }
        return
      }

      // Validate that we have at least one user message
      guard conversationHistoryForRequest.contains(where: { $0.role == .user }) else {
        aiErrorMessage = AIServiceError.emptyConversation.localizedDescription
        isGeneratingAI = false
        if let (conversationSnapshot, observationSnapshot) = rollbackSnapshot {
          conversationMessages = conversationSnapshot
          observationText = observationSnapshot
        }
        return
      }

      // Create empty assistant message first (triggers loading indicator)
      let isFirstAssistantMessage = !conversationMessages.contains { $0.role == .assistant }

      let messageIndex: Int
      let didCreatePlaceholderAssistant: Bool
      if let replacingAssistantMessageId,
        let existingIndex = conversationMessages.firstIndex(where: {
          $0.id == replacingAssistantMessageId && $0.role == .assistant
        })
      {
        conversationMessages[existingIndex].content = ""
        messageIndex = existingIndex
        didCreatePlaceholderAssistant = false
      } else if let lastMessage = conversationMessages.last,
        lastMessage.role == .assistant,
        lastMessage.content.isEmpty
      {
        // Reuse the existing empty assistant message
        conversationMessages[conversationMessages.count - 1].content = ""
        messageIndex = conversationMessages.count - 1
        didCreatePlaceholderAssistant = false
      } else {
        // Create a new empty assistant message
        let aiMessage = DialogueMessage(role: .assistant, content: "")
        conversationMessages.append(aiMessage)
        messageIndex = conversationMessages.count - 1
        didCreatePlaceholderAssistant = true
      }

      // Stream response updates into the placeholder assistant message.
      // AIService passes cumulative text snapshots, so assigning `chunk`
      // replaces the visible content with the latest complete prefix.
      let streamStart = CFAbsoluteTimeGetCurrent()
      var completedResponse = ""
      let updatedSummary = try await aiService.generateGoDeeperResponseStream(
        entryId: entryId,
        entryText: entryText,
        conversationHistory: conversationHistoryForRequest,
        currentSummary: conversationSummary,
        seedLensHint: promptSeed.map { seed -> String in
          // Compose the seed lens. Two lines for clusters with more than
          // one sub-state; one line otherwise. Keep it directional — no
          // verbatim opener echo (the model already sees it as the first
          // assistant message in conversation history), no instructions
          // (the system prompt covers routing).
          let clusterLine: String
          if seed.cluster == .time {
            let hour = Calendar.current.component(.hour, from: Date())
            clusterLine = seed.cluster.timeAiLensHint(forHour: hour)
          } else {
            clusterLine = seed.cluster.aiLensHint
          }
          if seed.cluster.subStates.count <= 1 {
            return clusterLine
          }
          return "\(clusterLine)\n\(seed.subState.aiLensHint)"
        },
        onChunk: { [weak self] chunk in
          guard let self = self else { return }

          completedResponse = chunk

          let ttft = Int((CFAbsoluteTimeGetCurrent() - streamStart) * 1000)
          Task { @MainActor in
            if messageIndex < self.conversationMessages.count {
              self.conversationMessages[messageIndex].content = chunk
              self.conversationMessages[messageIndex].durationMs = ttft
              HapticManager.shared.streamTick()
            }
          }
        },
        onSummaryCreated: { [weak self] newSummary in
          Task { @MainActor in
            guard let self,
              newSummary.summarizedMessageCount <= self.conversationMessages.count
            else { return }
            self.conversationSummary = newSummary
            self.onConversationUpdated?()
          }
        }
      )

      // Update summary if it was returned
      if let summary = updatedSummary {
        conversationSummary = summary
      }

      // Sync: ensure message content is set (the Task { @MainActor } dispatch
      // from onChunk may still be pending). We're on MainActor here, so this
      // assignment is synchronous and guaranteed.
      if messageIndex < conversationMessages.count {
        conversationMessages[messageIndex].content = completedResponse
      }

      // ── Fail-closed: don't commit empty responses ──
      let assembledContent = completedResponse
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !assembledContent.isEmpty else {
          if restoreInPlaceSnapshotIfNeeded() {
            // Restored from snapshot
          } else if didCreatePlaceholderAssistant {
            conversationMessages.removeLast()
          }
          aiErrorMessage = appLocalizedString(Localizable.errorAIService)
          isGeneratingAI = false
          return
        }

      // Track AI response generation
      AnalyticsTracker.shared.recordAIResponse()

      // Track go deeper for product analytics
      let responseNumber = conversationMessages.filter { $0.role == .assistant }.count
      Analytics.goDeeper(responseNumber: responseNumber)
      let latencyMs = messageIndex < conversationMessages.count
        ? conversationMessages[messageIndex].durationMs
        : nil
      Analytics.goDeeperCompleted(
        responseNumber: responseNumber,
        trigger: context.trigger,
        latencyMs: latencyMs,
        responseLength: assembledContent.count,
        hasSummary: conversationSummary != nil,
        isFirstAssistantMessage: isFirstAssistantMessage
      )

      // Record question count for premium users (200 responses/day)
      await AIQuotaManager.shared.recordAIResponse()

      // Track conversation start once per thread
      if isFirstAssistantMessage {
        AnalyticsTracker.shared.recordConversation()
      }

      inPlaceRegenerationSnapshot = nil
      lastGenerationContext = nil
      isGeneratingAI = false

      onConversationUpdated?()

    } catch is CancellationError {
      // Cancellation is normal flow: user navigated away or tapped Go Deeper again.
      // Do NOT roll back state — a newer request may already be in flight with its
      // own messages appended. Just clean up loading state silently.
      let didRestoreSnapshot = restoreInPlaceSnapshotIfNeeded()
      isGeneratingAI = false
      Analytics.goDeeperCancelled(
        responseNumber: nextResponseNumber(for: conversationMessages),
        trigger: context.trigger,
        hadPlaceholderAssistant: !didRestoreSnapshot,
        wasInPlaceRegeneration: context.replacingAssistantMessageId != nil
      )
    } catch let urlError as URLError where urlError.code == .cancelled {
      // URLSession surfaces cancellation as URLError.cancelled (-999), not
      // CancellationError. Same semantics: silent return, no rollback.
      let didRestoreSnapshot = restoreInPlaceSnapshotIfNeeded()
      isGeneratingAI = false
      Analytics.goDeeperCancelled(
        responseNumber: nextResponseNumber(for: conversationMessages),
        trigger: context.trigger,
        hadPlaceholderAssistant: !didRestoreSnapshot,
        wasInPlaceRegeneration: context.replacingAssistantMessageId != nil
      )
    } catch {
      let (message, retryAfter) = userFacingAIError(from: error)
      aiErrorMessage = message
      if let retryAfter {
        errorRetryAvailableAt = Date().addingTimeInterval(retryAfter)
      }
      isGeneratingAI = false
      AppLogger.ai.error("Error generating AI response: \(error)")
      let responseNumber = nextResponseNumber(for: conversationMessages)
      Analytics.aiError(
        reason: normalizedAnalyticsReason(for: error),
        stage: .generation,
        trigger: context.trigger,
        responseNumber: responseNumber,
        isRetryable: isRetryableAnalyticsError(error)
      )

      if restoreInPlaceSnapshotIfNeeded() {
        // Restored from in-place snapshot
      } else if let lastMessage = conversationMessages.last,
        lastMessage.role == .assistant,
        lastMessage.content.isEmpty
      {
        // Remove the empty assistant message — errors are shown via aiErrorMessage,
        // not as conversation content (prevents saving error text to the database)
        conversationMessages.removeLast()
      } else if let (conversationSnapshot, observationSnapshot) = rollbackSnapshot {
        conversationMessages = conversationSnapshot
        observationText = observationSnapshot
        onObservationRollback?(observationSnapshot)
      }
    }
  }
}

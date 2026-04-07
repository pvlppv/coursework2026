import Foundation
import os
import SwiftUI

@Observable
final class EditEntryViewModel {
  // MARK: - Published Properties

  // Text content
  var observation = ""
  var comment = ""
  var extractedValue = ""

  // Date selection
  var selectedDate = Date()
  var showDatePicker = false


  // Delete confirmation
  var showingDeleteAlert = false

  // MARK: - GoDeeper Engine

  /// Shared conversation engine — single source of truth for AI conversation logic.
  /// Recreated in `initializeWithEntry()` with the real entry ID for correct quota tracking.
  private(set) var engine: GoDeeperEngine

  // Entry ID for quota tracking
  var entryId: String?

  // Snapshot of original state for change detection
  private var originalObservation = ""
  private var originalComment = ""
  private var originalDate = Date()
  private var originalConversationHash = 0

  // MARK: - Proxied Engine Properties (Views access these through viewModel.*)

  var conversationMessages: [DialogueMessage] {
    get { engine.conversationMessages }
    set { engine.conversationMessages = newValue }
  }

  var conversationSummary: ConversationSummary? {
    get { engine.conversationSummary }
    set { engine.conversationSummary = newValue }
  }

  var isGeneratingAI: Bool { engine.isGeneratingAI }
  var aiErrorMessage: String? { engine.aiErrorMessage }
  var errorRetryAvailableAt: Date? { engine.errorRetryAvailableAt }
  var isAIResponseLimitError: Bool { engine.isAIResponseLimitError }
  var currentRequestTask: Task<Void, Never>? { engine.currentRequestTask }
  var isRateLimitCoolingDown: Bool { engine.isRateLimitCoolingDown }

  // MARK: - Computed Properties

  var isValidEntry: Bool {
    return !observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !conversationMessages.isEmpty
  }

  var hasUnsavedChanges: Bool {
    return observation != originalObservation
      || comment != originalComment
      || selectedDate != originalDate
      || conversationHash != originalConversationHash
  }

  /// Hash of conversation content for change detection.
  /// Detects both message count changes AND content edits.
  private var conversationHash: Int {
    var hasher = Hasher()
    for msg in conversationMessages {
      hasher.combine(msg.content)
      hasher.combine(msg.role)
    }
    return hasher.finalize()
  }

  var formattedDate: String {
    return DateFormatter.formatDateTimeForEntry(selectedDate)
  }

  // MARK: - Initialization

  init() {
    // Engine with temporary ID; will be replaced in initializeWithEntry
    self.engine = GoDeeperEngine(entryId: UUID().uuidString)
  }

  // MARK: - Entry Initialization

  func initializeWithEntry(_ entry: Entry) {
    // Populate common fields from the existing entry
    let id = entry.id.uuidString
    entryId = id
    comment = entry.comment ?? ""
    selectedDate = entry.date
    extractedValue = entry.extractedValue.map { "\($0)" } ?? ""

    // Recreate engine with the real entry ID for correct quota tracking
    self.engine = GoDeeperEngine(entryId: id)
    engine.onObservationRollback = { [weak self] text in
      self?.observation = text
    }

    // Initialize engine with existing conversation data
    engine.conversationMessages = entry.conversation
    engine.conversationSummary = entry.conversationSummary

    // Load canonical original text for existing entries with conversations
    if !entry.conversation.isEmpty {
      engine.setCachedOriginalEntryText(entry.canonicalOriginalText)
    }

    // Load draft first to check if there's work-in-progress text
    let draftText = loadDraft()

    // If there's a draft, use it (preserves work-in-progress)
    if let draft = draftText {
      observation = draft
    } else if entry.conversation.isEmpty {
      // No draft and no conversation - use entry's observation
      observation = entry.observation
    } else {
      // No draft but conversation exists - start with empty field
      observation = ""
    }

    // Save snapshot of initial state for change detection
    updateSnapshot()
  }

  /// Updates the full snapshot to reflect the current persisted state.
  /// Call this after an explicit user Save to reset all change detection.
  func updateSnapshot() {
    originalObservation = observation
    originalComment = comment
    originalDate = selectedDate
    originalConversationHash = conversationHash
  }

  /// Updates only the conversation part of the snapshot.
  /// Call this after AI-driven auto-saves so that
  /// user-authored dirty state (observation, comment, date) is preserved.
  func updateConversationSnapshot() {
    originalConversationHash = conversationHash
  }

  // MARK: - Draft Management (just the observation text field)

  private func loadDraft() -> String? {
    guard let id = entryId else {
      return nil
    }
    return DraftManager.shared.loadEditEntryDraft(entryId: id)
  }

  func saveDraft() {
    guard let id = entryId else { return }

    // Only save if there's actual text to preserve
    let trimmedText = observation.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedText.isEmpty {
      DraftManager.shared.saveEditEntryDraft(entryId: id, observation: observation)
    } else {
      // Clear draft if observation is empty
      DraftManager.shared.clearEditEntryDraft(entryId: id)
    }
  }

  func clearDraft() {
    guard let id = entryId else { return }
    DraftManager.shared.clearEditEntryDraft(entryId: id)
  }

  // MARK: - Date Management

  func changeDate() {
    HapticManager.shared.light()
    showDatePicker = true
  }

  // MARK: - Entry Management

  // MARK: - GoDeeper Methods (delegated to engine)

  func startGoDeeper() {
    engine.observationText = observation
    engine.startGoDeeper()
    observation = engine.observationText
  }

  func sendMessageAndContinue(focusedMessageId: UUID?) {
    engine.observationText = observation
    engine.sendMessageAndContinue(focusedMessageId: focusedMessageId)
    observation = engine.observationText
  }

  func clearAIError() {
    engine.clearAIError()
  }

  func cancelStreaming() {
    engine.cancelStreaming()
  }

  func retryLastGeneration() {
    engine.retryLastGeneration()
  }

  // MARK: - Message Editing Methods
  // Removed - editing is now handled directly in InlineConversationView bindings

  func updateEntry(_ entry: Entry) {
    let trimmedObservation = observation.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)

    // Collect all user messages from conversation
    var finalObservation = trimmedObservation
    if !conversationMessages.isEmpty {
      let userMessages =
        conversationMessages
        .filter { $0.role == .user }
        .map { $0.content }

      if !userMessages.isEmpty {
        // Only use committed user messages — unsent observation text
        // is preserved via draft, not folded into observation string
        finalObservation = userMessages.joined(separator: " ")
      }
    }

    // Update the existing entry
    entry.observation = finalObservation
    entry.comment = trimmedComment.isEmpty ? nil : trimmedComment
    entry.date = selectedDate
    entry.extractedValue = extractedValue.isEmpty ? nil : Double(extractedValue)

    // Save conversation if exists
    if !conversationMessages.isEmpty {
      entry.conversation = conversationMessages
      // Backfill canonical original text for legacy entries
      if entry.originalEntryText == nil, let originalText = engine.cachedOriginalEntryText {
        entry.originalEntryText = originalText
      }
    }

    // Save conversation summary if exists
    entry.conversationSummary = conversationSummary
  }

  /// Persists ONLY AI-derived data (conversation messages + summary) without
  /// touching user-authored fields (observation, comment, date).
  /// Use this for background auto-saves triggered by AI events.
  func updateConversationOnly(_ entry: Entry) {
    if !conversationMessages.isEmpty {
      entry.conversation = conversationMessages
    }
    entry.conversationSummary = conversationSummary
  }

  // MARK: - Delete Management

  func showDeleteConfirmation() {
    HapticManager.shared.light()
    showingDeleteAlert = true
  }

  func confirmDelete() {
    HapticManager.shared.medium()
    // The actual deletion will be handled by the parent view
  }

  // MARK: - Validation

  func validateEntry() -> Bool {
    return isValidEntry
  }

}

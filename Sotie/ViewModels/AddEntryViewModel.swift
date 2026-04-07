import Foundation
import os
import SwiftUI

@Observable
final class AddEntryViewModel {
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

  // MARK: - Prompt Seeding

  /// The clusters rendered in the rail. Built once per session from the
  /// shuffler so the user sees the same cards if they reopen AddEntry.
  let promptRail: [PromptCluster]

  /// Currently selected cluster (drives seed bubble and card highlight).
  /// nil = empty state.
  private(set) var selectedCluster: PromptCluster?

  /// The picked sub-state's `imageName`, used by the rail to swap the
  /// selected cluster card's illustration (icon variety). nil when no
  /// cluster is selected, or when the cluster has only one sub-state and
  /// the default illustration is already correct.
  private(set) var selectedSubStateImageOverride: String?

  /// Random illustration per cluster, assigned at init (sheet open). Each
  /// multi-sub-state cluster gets a random sub-state's imageName so the
  /// rail looks different every session. Single-sub-state clusters (time,
  /// brainDump) use their default illustration and are not in this map.
  private(set) var randomIllustrations: [PromptCluster: String]

  /// Tracks the current illustration index per cluster for deterministic
  /// cycling. Each tap advances to the next sub-state illustration,
  /// guaranteeing a visual change every time.
  private var illustrationIndices: [PromptCluster: Int] = [:]

  /// Recent opener "global indices" per cluster, used to weight away from
  /// repeats when the user re-taps the same cluster to regenerate.
  /// Encoded as `subStateIndex * 100 + openerIndex` so a single array per
  /// cluster covers all of its sub-states.
  private var recentOpenerIndices: [PromptCluster: [Int]] = [:]

  /// In-flight reveal task. Cancelled and replaced on every new card tap so
  /// rapid switching never lets a stale task flip `isSeedRevealing` off
  /// while a fresh cascade is mid-flight.
  @ObservationIgnored private var revealTask: Task<Void, Never>?

  // MARK: - GoDeeper Engine

  /// Shared conversation engine — single source of truth for AI conversation logic.
  let engine: GoDeeperEngine

  /// True while the synthetic seed reveal animation is in progress. Drives
  /// the same `isStreaming` binding `InlineConversationView` uses for real
  /// streamed responses, so the seed bubble inherits the sparkle pulse +
  /// blur reveal cascade automatically.
  var isSeedRevealing: Bool = false

  /// Convenience: `true` when either real AI streaming or synthetic seed
  /// reveal is happening. The conversation view treats both identically.
  var isStreamingOrRevealing: Bool { isGeneratingAI || isSeedRevealing }

  // Stable session ID for quota tracking
  private let sessionId = UUID().uuidString

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
    let hasObservationText = !observation
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    if hasObservationText { return true }
    // Only consider the conversation valid if the user has actually replied.
    // A lone assistant seed bubble is not enough to save an entry.
    return conversationMessages.contains { $0.role == .user }
  }

  var hasUnsavedChanges: Bool {
    let hasObservationText = !observation
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    if hasObservationText { return true }
    // A bare prompt seed alone is not "unsaved changes" — it's part of the
    // empty state. Only a real user reply counts.
    return conversationMessages.contains { $0.role == .user }
  }

  var formattedDate: String {
    return DateFormatter.formatDateTimeForEntry(selectedDate)
  }

  // MARK: - Initialization

  init() {
    self.engine = GoDeeperEngine(entryId: sessionId)
    // Build the prompt rail once at sheet open time. Engagement context
    // comes from the on-disk cluster stats; time + entry-count seed keeps
    // the rail stable within a session.
    self.promptRail = PromptShuffler.buildRail(
      context: PromptShuffleContext.current(
        stats: ClusterStatsStore.shared.load()
      )
    )
    // Assign a random sub-state illustration per multi-sub-state cluster.
    // This makes the rail look slightly different every time the sheet opens.
    // Exclude the time cluster — it resolves its illustration by hour, not
    // randomly (showing an evening icon in the morning would be confusing).
    var illustrations: [PromptCluster: String] = [:]
    var indices: [PromptCluster: Int] = [:]
    for cluster in promptRail where cluster.subStates.count > 1 && cluster != .time {
      let startIndex = Int.random(in: 0..<cluster.subStates.count)
      illustrations[cluster] = cluster.subStates[startIndex].imageName
      indices[cluster] = startIndex
    }
    self.randomIllustrations = illustrations
    self.illustrationIndices = indices

    engine.onObservationRollback = { [weak self] text in
      self?.observation = text
    }
    loadDraft()
    restorePromptDraftIfNeeded()

    // Track which clusters were shown on this session's rail.
    Analytics.promptRailImpression(clusters: promptRail.map(\.rawValue))
  }

  // MARK: - Draft Management (just the observation text field)

  private func loadDraft() {
    if let draftText = DraftManager.shared.loadAddEntryDraft() {
      observation = draftText
    }
  }

  func saveDraft() {
    // Only save if there's actual text to preserve
    let trimmedText = observation.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedText.isEmpty {
      DraftManager.shared.saveAddEntryDraft(observation: observation)
    } else {
      // Clear draft if observation is empty
      DraftManager.shared.clearAddEntryDraft()
    }
  }

  func clearDraft() {
    DraftManager.shared.clearAddEntryDraft()
    DraftManager.shared.clearPromptDraft()
  }

  // MARK: - Prompt Seeding

  /// Whether the cards rail should be visible. True only in the "empty"
  /// or "seeded but unreplied" states.
  var showsPromptRail: Bool {
    guard observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    let userMessages = conversationMessages.filter { $0.role == .user }
    return userMessages.isEmpty
  }

  /// Tap handler for a cluster card. Three behaviors:
  ///   - tap on a different cluster → seed with a fresh opener
  ///   - tap on the currently-selected cluster → deselect (clears the seed)
  ///   - tap when no cluster is selected → seed
  ///
  /// Re-tapping the same cluster as a "re-roll" was removed because users
  /// expect tap-to-deselect; if regenerate-without-leaving is needed, add
  /// a refresh control on the seeded card later.
  func selectCluster(_ cluster: PromptCluster) {
    if selectedCluster == cluster {
      deselectCluster()
      Analytics.promptCardDeselected(cluster: cluster.rawValue)
      return
    }

    let languageCode = LanguageManager.storedOrDefaultLanguageCode()
    let recents = recentOpenerIndices[cluster] ?? []
    // Seed the RNG with current time so successive taps roll distinct openers.
    let seed = UInt64(bitPattern: Int64(Date().timeIntervalSince1970 * 1000))

    let pick: (subState: PromptCategory, openerIndex: Int, text: String)?
    if cluster == .time {
      let hour = Calendar.current.component(.hour, from: Date())
      pick = PromptCatalog.opener(
        forTime: hour,
        languageCode: languageCode,
        seed: seed,
        recentlyShownGlobalIndices: recents
      )
    } else {
      pick = PromptCatalog.opener(
        for: cluster,
        languageCode: languageCode,
        seed: seed,
        recentlyShownGlobalIndices: recents
      )
    }

    guard let resolved = pick else {
      // Time-cluster picker returns nil at midday (no time card today).
      // Should be unreachable since the rail wouldn't have surfaced a
      // time card in that case, but guard rather than crash.
      AppLogger.data.warning("PromptCatalog returned nil for cluster=\(cluster.rawValue)")
      return
    }

    selectedCluster = cluster
    // Cycle to the next sub-state illustration deterministically.
    // Guarantees a visual change on every tap. Only for clusters with
    // multiple sub-states that aren't time-based (time resolves by hour).
    if cluster.subStates.count > 1 && cluster != .time {
      let currentIndex = illustrationIndices[cluster] ?? 0
      let nextIndex = (currentIndex + 1) % cluster.subStates.count
      illustrationIndices[cluster] = nextIndex
      let nextSubState = cluster.subStates[nextIndex]
      selectedSubStateImageOverride = nextSubState.imageName
      // Also update the random illustrations map so the card shows the new one
      randomIllustrations[cluster] = nextSubState.imageName
    } else {
      selectedSubStateImageOverride = nil
    }

    let globalIdx = PromptCatalog.globalIndex(
      forSubState: resolved.subState,
      openerIndex: resolved.openerIndex
    )
    var recentsForCluster = recentOpenerIndices[cluster, default: []]
    recentsForCluster.append(globalIdx)
    if recentsForCluster.count > 5 {
      recentsForCluster.removeFirst(recentsForCluster.count - 5)
    }
    recentOpenerIndices[cluster] = recentsForCluster

    DraftManager.shared.savePromptDraft(
      clusterId: cluster.rawValue,
      subStateId: resolved.subState.rawValue,
      openerText: resolved.text,
      openerIndex: resolved.openerIndex
    )

    ClusterStatsStore.shared.recordPick(cluster)

    Analytics.promptCardTapped(
      cluster: cluster.rawValue,
      subState: resolved.subState.rawValue,
      openerIndex: resolved.openerIndex,
      hour: Calendar.current.component(.hour, from: Date())
    )

    // Cancel any in-flight reveal so a stale task can't flip the streaming
    // flag off mid-cascade when the user taps cards in rapid succession.
    revealTask?.cancel()

    // Two-step seed for streaming-style reveal:
    //  1. Engine inserts an empty assistant bubble — sparkle pulses on it.
    //  2. After a short "thinking" delay we set the bubble's content; that
    //     transition (empty → non-empty under isStreaming==true) triggers
    //     the AIMessageRow blur cascade.
    engine.seedWithPrompt(
      cluster: cluster,
      subState: resolved.subState,
      openerText: resolved.text,
      openerIndex: resolved.openerIndex,
      revealMode: .streamingPlaceholder
    )
    isSeedRevealing = true

    let pickedText = resolved.text
    revealTask = Task { @MainActor in
      // Sparkle "thinks" briefly before the text reveal kicks in.
      // Two yields keep the empty-content state on screen long enough for
      // SwiftUI to commit it before we fill the bubble — without this,
      // rapid card switching can coalesce the empty→full diff into one
      // change and skip the AIMessageRow cascade trigger.
      await Task.yield()
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(450))
      if Task.isCancelled { return }

      self.engine.commitSeedReveal(text: pickedText)

      // Hold the streaming flag for the cascade duration so AIMessageRow
      // runs the same blur/cascade it does for real streamed responses.
      let revealSeconds = max(0.6, Double(pickedText.count) * 0.025)
      try? await Task.sleep(for: .seconds(revealSeconds))
      if Task.isCancelled { return }
      self.isSeedRevealing = false
    }
  }

  /// Clear the current prompt seed and selection. Cancels any in-flight
  /// reveal and discards the draft. Safe to call when no cluster is
  /// selected — it is a no-op in that case.
  ///
  /// We deliberately keep `selectedSubStateImageOverride` set: the rail
  /// card should hold its last-picked illustration so the visual doesn't
  /// flip back to the cluster default mid-deselect (which felt glitchy).
  /// The override is replaced on the next `selectCluster(...)` and cleared
  /// on `reset()`.
  func deselectCluster() {
    revealTask?.cancel()
    revealTask = nil
    isSeedRevealing = false
    selectedCluster = nil
    engine.clearPromptSeed()
    DraftManager.shared.clearPromptDraft()
  }

  /// Restore a previously seeded prompt from the draft store, if any.
  /// Called once at init. No-op if a stored draft cannot be resolved.
  private func restorePromptDraftIfNeeded() {
    guard let draft = DraftManager.shared.loadPromptDraft(),
      let cluster = PromptCluster(rawValue: draft.clusterId),
      let subState = PromptCategory(rawValue: draft.subStateId)
    else {
      return
    }

    // If the user already started typing into the observation field before
    // a force-quit, treat the prompt draft as stale and discard it. The
    // bubble would land above their freeform draft text and look broken.
    let hasFreeformText = !observation
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    if hasFreeformText {
      DraftManager.shared.clearPromptDraft()
      return
    }

    selectedCluster = cluster
    selectedSubStateImageOverride =
      cluster.subStates.count > 1 ? subState.imageName : nil
    let globalIdx = PromptCatalog.globalIndex(
      forSubState: subState,
      openerIndex: draft.openerIndex
    )
    recentOpenerIndices[cluster, default: []].append(globalIdx)
    engine.seedWithPrompt(
      cluster: cluster,
      subState: subState,
      openerText: draft.openerText,
      openerIndex: draft.openerIndex,
      revealMode: .immediate
    )
  }

  // MARK: - Date Management

  func changeDate() {
    HapticManager.shared.light()
    showDatePicker = true
  }

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
    // Also cancel any in-flight synthetic seed reveal — otherwise a stale
    // task can flip isSeedRevealing back on after the sheet has begun
    // dismissing, or write into the engine after it's been reset.
    revealTask?.cancel()
    revealTask = nil
    isSeedRevealing = false
    engine.cancelStreaming()
  }

  func retryLastGeneration() {
    engine.retryLastGeneration()
  }

  // MARK: - Entry Creation

  func createEntry() -> Entry {
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

    let entry = Entry(
      observation: finalObservation,
      comment: trimmedComment.isEmpty ? nil : trimmedComment,
      date: selectedDate,
      extractedValue: extractedValue.isEmpty ? nil : Double(extractedValue)
    )


    // Save conversation if exists
    if !conversationMessages.isEmpty {
      entry.conversation = conversationMessages
      // Override init default with the canonical original text
      if let originalText = engine.cachedOriginalEntryText {
        entry.originalEntryText = originalText
      }
    }

    // Save conversation summary if exists
    if let summary = conversationSummary {
      entry.conversationSummary = summary
    }

    // Persist prompt-seed metadata when the entry was started from a card.
    if let seed = engine.promptSeed {
      entry.promptText = seed.openerText
      entry.promptClusterId = seed.cluster.rawValue
      entry.promptCategoryId = seed.subState.rawValue
      entry.promptOpenerIndex = seed.openerIndex

      let userReplied = conversationMessages.contains { $0.role == .user }
      Analytics.promptSeedCommitted(
        cluster: seed.cluster.rawValue,
        subState: seed.subState.rawValue,
        openerIndex: seed.openerIndex,
        userReplied: userReplied
      )
    }

    return entry
  }

  // MARK: - Reset Methods

  func reset() {
    observation = ""
    comment = ""
    extractedValue = ""
    selectedDate = Date()
    selectedCluster = nil
    selectedSubStateImageOverride = nil
    recentOpenerIndices = [:]
    revealTask?.cancel()
    revealTask = nil
    isSeedRevealing = false
    engine.reset()
  }

  // MARK: - Delete Management

  func showDeleteConfirmation() {
    HapticManager.shared.light()
    showingDeleteAlert = true
  }

  func confirmDelete() {
    HapticManager.shared.medium()
    // Clear all content and reset the view model
    reset()
    clearDraft()
  }

  // MARK: - Validation

  func validateEntry() -> Bool {
    return isValidEntry
  }

}

import SwiftData
import SwiftUI

struct EditEntryView: View {
  let entry: Entry
  let onSave: (Entry) -> Void
  let onDelete: () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var viewModel = EditEntryViewModel()
  @State private var focusedMessageId: UUID?
  @State private var hasBeenSaved = false
  @State private var isInitialized = false
  @State private var showPaywall = false
  @State private var showDiscardConfirmation = false
  @State private var showFinishInsights = false
  @State private var showInsightsSheet = false

  @StateObject private var premiumManager = PremiumManager.shared
  @EnvironmentObject private var router: NavigationRouter

  var body: some View {
    NavigationStack {
      ZStack {
        // Main content
        VStack(spacing: 0) {
          // Dynamic input section based on table type
          inputSection
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(viewModel.formattedDate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          toolbarContent
        }

        // GoDeeper FAB - bottom right (always visible in edit mode)
        if shouldShowFAB {
          VStack {
            Spacer()
            HStack {
              Spacer()
              goDeeperFAB
                .padding(.trailing, Spacing.medium)
                .padding(.bottom, Spacing.large)
            }
          }
        }
      }
      .themeBackground(.primary)
      .alert(
        appLocalizedString(Localizable.deleteEntryTitle),
        isPresented: $viewModel.showingDeleteAlert
      ) {
        Button(appLocalizedString(Localizable.cancel), role: .cancel) {}
        Button(appLocalizedString(Localizable.delete), role: .destructive) {
          HapticManager.shared.error()
          viewModel.clearDraft()
          onDelete()
          dismiss()
        }
      } message: {
        Text(appLocalizedString(Localizable.deleteEntryMessage))
      }
    }
    .presentationDragIndicator(.visible)
    .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
    .background(SheetDismissGuard(onDismissAttempt: $showDiscardConfirmation))
    .alert(
      appLocalizedString(Localizable.finishReflection),
      isPresented: $showDiscardConfirmation
    ) {
      Button(appLocalizedString(Localizable.finish)) {
        handleFinish()
      }
      Button(appLocalizedString(Localizable.unsavedChangesDiscard), role: .destructive) {
        // Discard changes: cancel streaming, clear draft, dismiss without saving
        viewModel.cancelStreaming()
        viewModel.clearDraft()
        hasBeenSaved = true  // Prevent onDisappear from doing anything
        dismiss()
      }
    }
    .sheet(isPresented: $viewModel.showDatePicker) {
      NavigationStack {
        ZStack {
          Color.theme.backgroundPrimary.ignoresSafeArea()

          VStack {
            DatePicker(
              "",
              selection: $viewModel.selectedDate,
              displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, -20)
            .background(Color.clear)
          }
        }
        .navigationBarTitleDisplayMode(.inline)
        .presentationDragIndicator(.visible)
      }
      .presentationDetents([.medium])
    }
    .sheet(isPresented: $showPaywall) {
      PaywallView(source: .responseLimitReached)
    }
    .fullScreenCover(isPresented: $showFinishInsights) {
      FinishInsightsView(
        entryText: viewModel.engine.cachedOriginalEntryText
          ?? entry.canonicalOriginalText,
        messages: viewModel.conversationMessages,
        onDone: { insights in
          saveEntry(with: insights)
        },
        onSkip: {
          saveEntry(with: nil)
        }
      )
      .transition(.opacity)
    }
    .sheet(isPresented: $showInsightsSheet) {
      if let insights = entry.insights {
        ViewInsightsSheet(insights: insights)
          .onAppear { Analytics.insightsViewed() }
      }
    }
    .onAppear {
      // Initialize ViewModel with entry data
      viewModel.initializeWithEntry(entry)
      // Start tracking time spent editing
      AnalyticsTracker.shared.startEntrySession()

      // Clear notification indicator and cancel pending follow-up
      // when user opens the entry (they've already re-engaged).
      // Deferred to avoid modelContext.save() racing with sheet presentation,
      // which triggers @Query refresh in HomeView's List and causes layout jumps.
      if entry.notificationSentAt != nil {
        let entryId = entry.id
        Task { @MainActor in
          entry.notificationSentAt = nil
          NotificationScheduler.shared.cancelFollowUpForEntry(entryId)
          try? entry.modelContext?.save()
        }
      }

      // Defer initialization flag to next run loop so that the initial
      // conversationSummary onChange (nil→loaded value) is suppressed.
      Task { @MainActor in
        isInitialized = true
      }
    }
    .onChange(of: viewModel.conversationSummary) { _, newSummary in
      // Auto-save when conversation summary is updated (happens in background)
      // Guard: skip the initial population from initializeWithEntry();
      // only react to runtime changes (e.g. AI-generated summary)
      guard isInitialized, !hasBeenSaved, newSummary != nil else { return }
      viewModel.updateConversationOnly(entry)
      do { try entry.modelContext?.save() }
      catch { print("⚠️ Auto-save summary failed: \(error)") }
      // Update conversation snapshot only — preserve user-authored dirty state
      viewModel.updateConversationSnapshot()
    }
    .onChange(of: scenePhase) { _, newPhase in
      switch newPhase {
      case .background:
        // Pause timer and save draft when app goes to background
        AnalyticsTracker.shared.pauseSession()
        viewModel.saveDraft()
      case .active:
        // Resume timer when app returns to foreground
        AnalyticsTracker.shared.resumeSession()
      default:
        break
      }
    }
    .onDisappear {
      // Stop tracking time and save duration
      AnalyticsTracker.shared.endEntrySession()

      // Cancel any in-flight AI streaming gracefully
      viewModel.cancelStreaming()

      // If user explicitly saved, deleted, or discarded — nothing more to do
      if hasBeenSaved || viewModel.showingDeleteAlert {
        return
      }

      // Save draft for crash protection (preserves work-in-progress text)
      viewModel.saveDraft()

      // NOTE: No auto-save of entry here.
      // Saving only happens via explicit ✓ tap, confirmation dialog, or conversation auto-save.
    }
  }

  private var inputSection: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {

          if !viewModel.conversationMessages.isEmpty {
            InlineConversationView(
              messages: $viewModel.conversationMessages,
              focusedMessageId: $focusedMessageId,
              isStreaming: .constant(viewModel.isGeneratingAI)
            )
            // Breathing room between the last message and the textarea/
            // placeholder below — matches AddEntryView spacing for parity.
            .padding(.bottom, Spacing.xSmall)
          }

          // Error message – live countdown, auto-clears when timer expires
          if viewModel.aiErrorMessage != nil {
            TimelineView(.periodic(from: Date(), by: 1.0)) { _ in
              if let retryDate = viewModel.errorRetryAvailableAt {
                let secs = max(0, Int(retryDate.timeIntervalSinceNow.rounded(.up)))
                if secs > 0 {
                  Text(appLocalizedString(Localizable.errorRateLimited, arguments: secs))
                    .font(.footnote)
                    .italic()
                    .themeText(.secondary)
                    .opacity(0.6)
                    .padding(.horizontal, Spacing.medium)
                    .padding(.top, Spacing.xSmall)
                }
              } else {
                // Non-rate-limit error (network, etc.) – static message
                Text(viewModel.aiErrorMessage ?? "")
                  .font(.footnote)
                  .italic()
                  .themeText(.secondary)
                  .opacity(0.6)
                  .padding(.horizontal, Spacing.medium)
                  .padding(.top, Spacing.xSmall)
              }
            }
            .task(id: viewModel.errorRetryAvailableAt) {
              guard let retryDate = viewModel.errorRetryAvailableAt else { return }
              let remaining = retryDate.timeIntervalSinceNow
              if remaining <= 0 {
                viewModel.clearAIError()
                return
              }
              do {
                try await Task.sleep(for: .seconds(remaining))
                viewModel.clearAIError()
              } catch {
                // Task cancelled (view disappeared) — no-op
              }
            }
            .padding(.bottom, Spacing.xSmall)
          }

          noteEditorSection
        }
        .padding(.bottom, 100)  // Space for FAB
      }
    }
  }


  private var noteEditorSection: some View {
    ZStack(alignment: .topLeading) {
      if viewModel.observation.isEmpty {
        Text(placeholderText)
          .typography(.body)
          .themeText(.secondary)
          .padding(.horizontal, Spacing.medium)
          .padding(.vertical, Spacing.xxSmall)
          .allowsHitTesting(false)
      }

      TextField("", text: $viewModel.observation, axis: .vertical)
        .typography(.body)
        .themeText(.primary)
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.xxSmall)
        .accessibilityLabel(appLocalizedString(Localizable.journalEntry))
        .accessibilityIdentifier("journal-entry-field")
        .onChange(of: viewModel.observation) { _, _ in
          focusedMessageId = nil
        }
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      // Menu button (3 dots) — left side
      Menu {
        Button(action: {
          viewModel.changeDate()
        }) {
          Label(appLocalizedString(Localizable.changeDate), systemImage: "calendar")
        }

        // View Insights option (only when insights exist)
        if entry.insights != nil {
          Button(action: {
            showInsightsSheet = true
          }) {
            Label(appLocalizedString(Localizable.insightsViewMenu), systemImage: "sparkles")
          }
        }

        Divider()

        Button(
          role: .destructive,
          action: {
            viewModel.showDeleteConfirmation()
          }
        ) {
          Label(appLocalizedString(Localizable.deleteEntry), systemImage: "trash")
        }
      } label: {
        Image(systemName: "ellipsis")
      }
      .accessibilityLabel(appLocalizedString(Localizable.accessibilityMenuButton))
      .accessibilityHint(appLocalizedString(Localizable.accessibilityMenuButtonHint))
    }

    ToolbarItem(placement: .topBarTrailing) {
      // Finish button — right side
      Button(appLocalizedString(Localizable.finish)) {
        HapticManager.shared.soft()
        handleFinish()
      }
      .fontWeight(.semibold)
      .disabled(!viewModel.isValidEntry || hasBeenSaved)
      .accessibilityIdentifier("finish-reflection-button")
    }
  }

  private var placeholderText: String {
    if viewModel.conversationMessages.isEmpty {
      return appLocalizedString(Localizable.notePlaceholderInitial)
    } else {
      return appLocalizedString(Localizable.notePlaceholder)
    }
  }

  private var shouldShowFAB: Bool {
    let hasObservation = !viewModel.observation.trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    let hasMessageContent = viewModel.conversationMessages.contains {
      !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    // Also show FAB when there's an error so user can see the retry button
    return hasObservation || hasMessageContent || viewModel.aiErrorMessage != nil
  }

  private var isFABDisabled: Bool {
    viewModel.isGeneratingAI || viewModel.isRateLimitCoolingDown || hasBeenSaved
  }

  private var goDeeperFAB: some View {
    Button {
      HapticManager.shared.medium()
      handleGoDeeper()
    } label: {
      Image(systemName: viewModel.aiErrorMessage != nil ? "arrow.clockwise" : "sparkles")
        .font(.title2)
        .foregroundStyle(Color.theme.buttonText)
        .frame(width: 28, height: 28)
    }
    .buttonStyle(.glassProminent)
    .buttonBorderShape(.circle)
    .controlSize(.large)
    .tint(Color.theme.buttonBackground)
    .opacity(isFABDisabled ? 0.45 : 1)
    .allowsHitTesting(!isFABDisabled)
    .accessibilityIdentifier("go-deeper-fab")
    .animation(.easeInOut(duration: 0.2), value: isFABDisabled)
  }

  // MARK: - Actions

  private func handleGoDeeper() {
    // Free users: block AI entirely, show paywall
    if !premiumManager.subscriptionStatus.isPremium {
      showPaywall = true
      return
    }

    // If there's an error, check if it's a response limit error
    if viewModel.aiErrorMessage != nil {
      // For free users hitting response limit, show paywall
      if viewModel.isAIResponseLimitError && !premiumManager.subscriptionStatus.isPremium {
        showPaywall = true
        return
      }

      // For other errors or premium users, retry
      viewModel.clearAIError()
      viewModel.retryLastGeneration()
      return
    }

    if !viewModel.conversationMessages.isEmpty {
      let hasObservation = !viewModel.observation.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty

      if focusedMessageId != nil {
        // Sending focused message - clear observation and draft
        viewModel.observation = ""
        viewModel.clearDraft()
        viewModel.sendMessageAndContinue(focusedMessageId: focusedMessageId)
      } else if hasObservation {
        // Sending from observation - clear focus and draft
        focusedMessageId = nil
        viewModel.clearDraft()
        viewModel.sendMessageAndContinue(focusedMessageId: nil)
      } else {
        // Empty observation and no focus - use last user message
        viewModel.clearDraft()  // Clear draft even though it's empty
        let lastUserMessageId = viewModel.conversationMessages.last {
          $0.role == .user
        }?.id
        viewModel.sendMessageAndContinue(focusedMessageId: lastUserMessageId)
      }
    } else {
      // Starting new conversation - clear draft
      viewModel.clearDraft()
      viewModel.startGoDeeper()
    }
  }

  private func handleFinish() {
    // If there's an active conversation with AI responses, check if insights need generation
    let hasConversation = viewModel.conversationMessages.contains { $0.role == .assistant && !$0.content.isEmpty }
    if hasConversation {
      // Check staleness: if insights exist and are fresh, just save
      let currentMessageCount = viewModel.conversationMessages.count
      if let existingInsights = entry.insights, !existingInsights.isStale(currentMessageCount: currentMessageCount) {
        // Insights are fresh — save directly without ceremony
        saveEntry(with: existingInsights)
      } else {
        // Insights are stale or don't exist — generate new ones
        viewModel.cancelStreaming()
        showFinishInsights = true
      }
    } else {
      // No conversation — just save directly
      saveEntry(with: nil)
    }
  }

  private func saveEntry(with insights: ConversationInsights? = nil) {
    // Guard against double-tap: once saved, never save again
    guard !hasBeenSaved else { return }
    hasBeenSaved = true

    // Gracefully cancel any in-flight AI streaming before saving
    viewModel.cancelStreaming()

    HapticManager.shared.success()

    // Update the existing entry using ViewModel
    viewModel.updateEntry(entry)

    // Attach insights if generated
    if let insights {
      entry.insights = insights
    }

    // Persist unsent observation text as draft so it reappears on reopen;
    // clear draft when there's nothing to preserve.
    let hasUnsentText = !viewModel.observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if hasUnsentText && !viewModel.conversationMessages.isEmpty {
      viewModel.saveDraft()
    } else {
      viewModel.clearDraft()
    }

    // Persist BEFORE dismiss to prevent data loss on app suspension
    onSave(entry)

    dismiss()
  }
}

#Preview {
  EditEntryView(
    entry: Entry(
      observation: "Sample note",
      comment: "Sample comment",
      date: Date(),
      extractedValue: 8.5
        // photoURLs: ["photo1"],
        // voiceRecordingURL: nil
    ),
    onSave: { _ in },
    onDelete: {}
  )
  .environment(\.theme, Theme())
}

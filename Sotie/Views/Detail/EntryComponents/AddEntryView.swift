import SwiftData
import SwiftUI

struct AddEntryView: View {
  let onSave: (Entry) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.composeCollapse) private var composeCollapse
  @Environment(\.composeIsExpanded) private var composeIsExpanded
  @Environment(\.scenePhase) private var scenePhase
  @State private var viewModel = AddEntryViewModel()
  @State private var focusedMessageId: UUID?
  @State private var hasBeenSaved = false
  @State private var showPaywall = false
  @State private var showDiscardConfirmation = false
  @State private var showFinishInsights = false
  @FocusState private var isTextFieldFocused: Bool

  @StateObject private var premiumManager = PremiumManager.shared

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

        // GoDeeper FAB - bottom right
        VStack {
          Spacer()
          HStack {
            Spacer()
            goDeeperFAB
              .padding(.trailing, Spacing.medium)
              .padding(.bottom, Spacing.large)
              .opacity(shouldShowFAB ? 1 : 0)
              .allowsHitTesting(shouldShowFAB)
              .animation(.easeInOut(duration: 0.15), value: shouldShowFAB)
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
          viewModel.confirmDelete()
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
        // Discard: cancel streaming, clear draft, dismiss without creating entry
        viewModel.cancelStreaming()
        viewModel.clearDraft()
        hasBeenSaved = true  // Prevent onDisappear from doing anything
        closeSheet()
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
          ?? viewModel.observation.trimmingCharacters(in: .whitespacesAndNewlines),
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
    .onAppear {
      // Start tracking time spent in entry creation
      AnalyticsTracker.shared.startEntrySession()

      // When standalone (no compose host), focus immediately. When hosted
      // inside ComposeSheet we wait for `composeIsExpanded` to flip true
      // — set by the host once the sheet is past peek.
      if composeCollapse == nil {
        DispatchQueue.main.async {
          isTextFieldFocused = true
        }
      }
    }
    .onChange(of: composeIsExpanded) { _, expanded in
      // Sync focus with the sheet's expand state. Setting focus here
      // (rather than in onAppear) avoids racing the sheet's height
      // animation, which is what was causing the keyboard to fail to
      // appear or appear inconsistently.
      if expanded {
        DispatchQueue.main.async {
          isTextFieldFocused = true
        }
      } else {
        isTextFieldFocused = false
      }
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

      // If user explicitly saved or discarded — nothing more to do
      if hasBeenSaved {
        return
      }

      // Save draft for crash protection (preserves work-in-progress text)
      viewModel.saveDraft()

      // NOTE: No auto-creation of entry here.
      // Entry creation only happens via explicit ✓ tap or confirmation dialog.
    }
  }

  private var inputSection: some View {
    ScrollViewReader { proxy in
      ScrollView {
        // Spacing 0: conversation flow (AI ↔ user ↔ textarea) is "sacred" —
        // it's all driven by the inner xxSmall vertical paddings each row
        // already owns. Extra inter-section breathing room (above/below the
        // rail) is added on the rail block itself.
        VStack(alignment: .leading, spacing: 0) {
          // Photos section removed — media features not active

          // Prompt cards rail (empty / seeded states only)
          if viewModel.showsPromptRail {
            PromptCardsRail(
              clusters: viewModel.promptRail,
              selectedCluster: viewModel.selectedCluster,
              selectedSubStateImageOverride: viewModel.selectedSubStateImageOverride,
              randomIllustrations: viewModel.randomIllustrations,
              hour: Calendar.current.component(.hour, from: Date()),
              onSelect: { cluster in
                viewModel.selectCluster(cluster)
              }
            )
            .padding(.bottom, Spacing.small)
            .transition(.promptRail)
          }

          if !viewModel.conversationMessages.isEmpty {
            InlineConversationView(
              messages: $viewModel.conversationMessages,
              focusedMessageId: $focusedMessageId,
              isStreaming: .constant(viewModel.isStreamingOrRevealing),
              // Suppress the satisfying stream-end haptic for synthetic
              // seed reveals. Using `isSeedRevealing` directly raced — the
              // flag flipped to false a beat before the streaming binding,
              // so by the time the haptic decision was made the gate was
              // already open. Stable signal: only allow the finish haptic
              // once the user has actually replied (real AI streaming).
              playFinishHaptic: viewModel.conversationMessages.contains { $0.role == .user }
            )
            // Breathing room between the last message and the textarea
            // below. Only added when there's a conversation above —
            // empty entries keep their original tight layout.
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
        // Use the same `.snappy` system spring on the parent reflow so the
        // AI message + placeholder ride alongside the rail with the same
        // motion character. One curve everywhere → coordinated feel.
        .animation(.snappy, value: viewModel.showsPromptRail)
      }
    }
  }


  private var noteEditorSection: some View {
    // Use SwiftUI's native `prompt:` parameter for the placeholder. The
    // overlay-via-ZStack approach was fragile: when the parent reflowed
    // (rail re-inserting, conversation expanding), the placeholder
    // sometimes detached from the cursor position. The native prompt is
    // anchored to the field's own first-line position by AppKit/UIKit.
    TextField(
      "",
      text: $viewModel.observation,
      prompt: Text(placeholderText)
        .foregroundColor(Color.theme.textSecondary),
      axis: .vertical
    )
    .typography(.body)
    .themeText(.primary)
    .padding(.horizontal, Spacing.medium)
    .padding(.vertical, Spacing.xxSmall)
    .focused($isTextFieldFocused)
    .accessibilityLabel(appLocalizedString(Localizable.journalEntry))
    .accessibilityIdentifier("journal-entry-field")
    .onChange(of: viewModel.observation) { _, _ in
      focusedMessageId = nil
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
    let hasUserReply = viewModel.conversationMessages.contains { $0.role == .user }
    return hasObservation || hasUserReply || viewModel.aiErrorMessage != nil
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
    // If there's an active conversation with AI responses, show insights flow
    let hasConversation = viewModel.conversationMessages.contains { $0.role == .assistant && !$0.content.isEmpty }
    if hasConversation {
      // Cancel streaming before entering finish flow
      viewModel.cancelStreaming()
      showFinishInsights = true
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

    let entry = viewModel.createEntry()

    // Attach insights if generated
    if let insights {
      entry.insights = insights
    }

    // Persist unsent observation text as edit-entry draft under the new entry's ID
    // so it reappears when the user reopens this entry in EditEntryView.
    let hasUnsentText = !viewModel.observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if hasUnsentText && !viewModel.conversationMessages.isEmpty {
      DraftManager.shared.saveEditEntryDraft(
        entryId: entry.id.uuidString, observation: viewModel.observation)
    }
    viewModel.clearDraft()  // Always clear the addEntry draft

    // Persist BEFORE dismiss to prevent data loss on app suspension
    onSave(entry)

    closeSheet()
  }

  /// Hosted inside ComposeSheet, `dismiss()` would tear down the persistent
  /// sheet. The host injects a collapse callback so we slide back to peek.
  private func closeSheet() {
    if let composeCollapse {
      composeCollapse()
    } else {
      dismiss()
    }
  }

}

#Preview {
  AddEntryView(
    onSave: { _ in }
  )
  .environment(\.theme, Theme())
  .modelContainer(for: Entry.self, inMemory: true)
}

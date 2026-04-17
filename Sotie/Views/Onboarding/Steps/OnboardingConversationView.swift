//
//  OnboardingConversationView.swift
//  Sotie
//
//
//  Screen 23: Interactive demo conversation within the new onboarding flow.
//  Uses GoDeeperEngine for real AI streaming. After 3 exchanges,
//  saves the conversation as the user's first entry and shows a
//  "Continue" footer for the user to advance.
//

import os
import SwiftData
import SwiftUI

struct OnboardingConversationView: View {
  let name: String
  let onBack: () -> Void
  let onContinue: () -> Void
  @Environment(\.modelContext) private var modelContext

  // MARK: - Phases

  enum Phase: Equatable {
    case welcome        // Sparkle → welcome streaming
    case ready          // User can type, FAB disabled until text entered
    case aiResponse     // Real AI streaming / conversation
    case done           // All rounds complete, show Continue footer
  }

  @State private var phase: Phase = .welcome
  @State private var userText = ""
  @FocusState private var isTextFieldFocused: Bool

  /// Guard to ensure we only persist the onboarding entry once.
  @State private var onboardingEntrySaved = false

  // MARK: - Round Tracking

  /// Number of AI responses allowed before showing Continue.
  private let maxRounds = 3
  /// Counter for how many AI responses have completed.
  @State private var aiResponseCount = 0

  // Welcome — DialogueMessage + AIMessageRow (reuses real blur-reveal animation)
  @State private var welcomeMessage = DialogueMessage(role: .assistant, content: "")
  @State private var isWelcomeStreaming = true

  // GoDeeper engine for real AI
  @State private var engine = GoDeeperEngine(
    entryId: "onboarding-\(UUID().uuidString)"
  )

  // Welcome fade-in
  @State private var welcomeVisible = false

  /// Timestamp when the demo conversation first appeared, used to compute the
  /// duration analytics signal at finish time.
  @State private var conversationStartedAt: Date?

  // MARK: - Computed

  private var isUserTextEmpty: Bool {
    userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var welcomeText: String {
    appLocalizedString(Localizable.onboardingFlowDemoWelcome, arguments: name)
  }

  // MARK: - Body

  var body: some View {
    NavigationStack {
      mainContent
        .themeBackground(.primary)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { navBarToolbar }
    }
    .opacity(welcomeVisible ? 1 : 0)
    .interactiveDismissDisabled(true)
    .onAppear {
      guard phase == .welcome else { return }
      aiResponseCount = 0
      engine.clearAIError()
      conversationStartedAt = Date()
      withAnimation(.easeInOut(duration: 0.4)) {
        welcomeVisible = true
      }
      startWelcomeStreaming()
    }
    .onDisappear {
      engine.currentRequestTask?.cancel()
    }
    .onChange(of: engine.isGeneratingAI) { _, isGenerating in
      if !isGenerating && phase == .aiResponse {
        // Quota limit → show Continue
        if engine.isAIResponseLimitError {
          AppLogger.ai.info("Onboarding demo: quota limit reached")
          engine.clearAIError()
          finishConversation()
          return
        }

        // Log errors
        if let errorMsg = engine.aiErrorMessage {
          AppLogger.ai.error("Onboarding demo AI error: \(errorMsg)")
        }

        // Only count successful AI responses
        guard engine.aiErrorMessage == nil else { return }
        aiResponseCount += 1
        AppLogger.ai.info("Onboarding demo: AI response \(aiResponseCount)/\(maxRounds) completed")

        if aiResponseCount >= maxRounds {
          if !PremiumManager.shared.subscriptionStatus.isPremium {
            PremiumManager.shared.markOnboardingAIDemoConsumed()
          }
          finishConversation()
        }
      }
    }
    .onChange(of: engine.isAIResponseLimitError) { _, isLimitError in
      if isLimitError && phase != .done {
        AppLogger.ai.info("Onboarding demo: AI response limit error")
        engine.clearAIError()
        finishConversation()
      }
    }
  }

  // MARK: - Main Content

  private var mainContent: some View {
    ZStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          // Welcome message (streamed word-by-word)
          AIMessageRow(
            message: welcomeMessage,
            isLastMessage: engine.conversationMessages.isEmpty,
            isStreaming: isWelcomeStreaming
          )
          // Air below the welcome bubble before the user reply / further
          // conversation begins. Matches AddEntry/EditEntry spacing.
          .padding(.bottom, Spacing.xSmall)

          // Real conversation messages
          if !engine.conversationMessages.isEmpty {
            InlineConversationView(
              messages: $engine.conversationMessages,
              focusedMessageId: .constant(nil),
              isStreaming: Binding(get: { engine.isGeneratingAI }, set: { _ in }),
              isEditable: false
            )
            .padding(.bottom, Spacing.xSmall)
          }

          // Error display with rate limit countdown
          if engine.aiErrorMessage != nil {
            errorView
          }

          // Text input (visible in ready/aiResponse phases)
          if (phase == .ready || phase == .aiResponse) {
            textInputSection
              .transition(.opacity)
          }
        }
        .padding(.bottom, phase == .done ? 220 : 100)
      }
      .scrollIndicators(.hidden)

      // FAB — visible in ready/aiResponse, disabled until user types
      if phase == .ready || phase == .aiResponse {
        VStack {
          Spacer()
          HStack {
            Spacer()
            goDeeperFAB
              .padding(.trailing, Spacing.medium)
              .padding(.bottom, Spacing.small)
          }
        }
      }

      // Continue footer — shown after all rounds complete and animation finishes
      if phase == .done {
        VStack(spacing: 0) {
          Spacer()

          LinearGradient(
            colors: [Color.theme.backgroundPrimary.opacity(0), Color.theme.backgroundPrimary],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 80)
          .allowsHitTesting(false)

          VStack(spacing: Spacing.medium) {
            // Explanation text
            VStack(spacing: Spacing.xxSmall) {
              Text(appLocalizedString(Localizable.onboardingFlowDemoFooterPrimary))
                .typography(.body)
                .fontWeight(.semibold)
                .themeText(.primary)
                .multilineTextAlignment(.center)

              Text(appLocalizedString(Localizable.onboardingFlowDemoFooterSecondary))
                .typography(.caption)
                .themeText(.secondary)
                .multilineTextAlignment(.center)
            }

            Button {
              HapticManager.shared.medium()
              onContinue()
            } label: {
              Text(appLocalizedString(Localizable.onboardingFlowContinue))
                .typography(.headline)
                .foregroundColor(Color.theme.buttonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                  RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                    .fill(Color.theme.buttonBackground)
                )
            }
          }
          .padding(.horizontal, Spacing.medium)
          .padding(.top, Spacing.medium)
          .padding(.bottom, Spacing.xLarge)
          .background(Color.theme.backgroundPrimary)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
  }

  // MARK: - Nav Bar Toolbar

  @ToolbarContentBuilder
  private var navBarToolbar: some ToolbarContent {
    ToolbarItem(placement: .navigationBarLeading) {
      Button {
        HapticManager.shared.soft()
        onBack()
      } label: {
        Image(systemName: "chevron.left")
          .font(.body.weight(.medium))
          .themeText(.primary)
      }
    }
  }

  // MARK: - Text Input

  private var textInputSection: some View {
    ZStack(alignment: .topLeading) {
      if userText.isEmpty {
        Text(appLocalizedString(Localizable.onboardingWriteHere))
          .typography(.body)
          .themeText(.secondary)
          .opacity(0.5)
          .padding(.horizontal, Spacing.medium)
          .padding(.vertical, Spacing.xxSmall)
          .allowsHitTesting(false)
      }

      TextField("", text: $userText, axis: .vertical)
        .typography(.body)
        .themeText(.primary)
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.xxSmall)
        .focused($isTextFieldFocused)
        .accessibilityLabel(Text(appLocalizedString(Localizable.journalEntry)))
    }
  }

  // MARK: - Error View

  private var errorView: some View {
    Group {
      TimelineView(.periodic(from: Date(), by: 1.0)) { _ in
        if let retryDate = engine.errorRetryAvailableAt {
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
          Text(engine.aiErrorMessage ?? "")
            .font(.footnote)
            .italic()
            .themeText(.secondary)
            .opacity(0.6)
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.xSmall)
        }
      }
      .task(id: engine.errorRetryAvailableAt) {
        guard let retryDate = engine.errorRetryAvailableAt else { return }
        let remaining = retryDate.timeIntervalSinceNow
        if remaining <= 0 {
          engine.clearAIError()
          return
        }
        do {
          try await Task.sleep(for: .seconds(remaining))
          engine.clearAIError()
        } catch {}
      }
    }
    .padding(.bottom, Spacing.xSmall)
  }

  // MARK: - Go Deeper FAB

  private var goDeeperFAB: some View {
    Button {
      // Error retry
      if engine.aiErrorMessage != nil && !engine.isAIResponseLimitError {
        AppLogger.ai.info("Onboarding demo: retrying after error")
        engine.clearAIError()
        engine.retryLastGeneration()
        return
      }

      handleGoDeeperTap()
    } label: {
      Image(systemName: engine.aiErrorMessage != nil ? "arrow.clockwise" : "sparkles")
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundColor(Color.theme.buttonText)
        .frame(width: 56, height: 56)
        .background(Circle().fill(Color.theme.buttonBackground))
    }
    .buttonStyle(PressableButtonStyle())
    .disabled(fabDisabled)
    .opacity(fabDisabled ? 0.4 : 1)
  }

  private var fabDisabled: Bool {
    if engine.aiErrorMessage != nil { return false }
    return isUserTextEmpty || engine.isGeneratingAI
  }

  // MARK: - Actions

  private func handleGoDeeperTap() {
    guard !isUserTextEmpty else { return }

    if phase == .ready {
      // First message — start the Go Deeper conversation
      phase = .aiResponse
      engine.observationText = userText.trimmingCharacters(in: .whitespacesAndNewlines)
      AppLogger.ai.info("Onboarding demo: starting Go Deeper")
      engine.startGoDeeper()
      userText = engine.observationText
      Analytics.goDeeper(responseNumber: 1)
    } else if phase == .aiResponse && !engine.isGeneratingAI {
      // Subsequent messages — continue conversation
      engine.observationText = userText.trimmingCharacters(in: .whitespacesAndNewlines)
      AppLogger.ai.info("Onboarding demo: continuing conversation")
      engine.sendMessageAndContinue(focusedMessageId: nil)
      userText = engine.observationText

      let responseNumber = engine.conversationMessages.filter { $0.role == .assistant }.count
      Analytics.goDeeper(responseNumber: responseNumber)
    }
  }

  /// Called when all rounds are done. Saves entry and shows Continue footer
  /// after the last AI response animation finishes.
  private func finishConversation() {
    guard phase != .done else { return }
    isTextFieldFocused = false
    saveOnboardingEntry()

    // Funnel: log how the demo concluded so we can see where users drop.
    let duration: Double = {
      guard let start = conversationStartedAt else { return 0 }
      return Date().timeIntervalSince(start)
    }()
    Analytics.onboardingDemoFinished(
      messageCount: engine.conversationMessages.count,
      durationSeconds: duration
    )

    // Wait for the blur-reveal animation to finish on the last AI response
    // before showing the footer (typical reveal: ~3s after streaming ends)
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
      HapticManager.shared.success()
      withAnimation(.easeOut(duration: 0.4)) {
        phase = .done
      }
    }
  }

  // MARK: - Welcome Streaming

  /// Delivers the welcome message using the same blur-reveal animation as real AI responses.
  /// AIMessageRow triggers the cascade when content goes from empty → non-empty while
  /// isStreaming is true, then the post-stream reveal kicks in when isStreaming becomes false.
  private func startWelcomeStreaming() {
    welcomeMessage = DialogueMessage(role: .assistant, content: "")
    isWelcomeStreaming = true

    // Sparkle breathing indicator shows for 2.5s
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
      // Set full content while isStreaming is still true — this triggers
      // AIMessageRow's blur-reveal cascade (content empty → non-empty)
      self.welcomeMessage.content = self.welcomeText

      // After a brief moment, signal "streaming ended" so the post-stream
      // reveal accelerates and finishes the cascade naturally
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self.isWelcomeStreaming = false

        // Wait for reveal to finish, then enable input
        let revealTime = min(4.0, Double(self.welcomeText.count) * 0.012 + 0.3)
        DispatchQueue.main.asyncAfter(deadline: .now() + revealTime) {
          withAnimation(.easeInOut(duration: 0.4)) {
            self.phase = .ready
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isTextFieldFocused = true
          }
        }
      }
    }
  }

  // MARK: - Persist Onboarding Conversation as Entry #1

  @discardableResult
  private func saveOnboardingEntry() -> Entry? {
    guard !onboardingEntrySaved else { return nil }
    guard !engine.conversationMessages.isEmpty else { return nil }

    onboardingEntrySaved = true

    let userMessages = engine.conversationMessages
      .filter { $0.role == .user }
      .map { $0.content }
    let observation = userMessages.joined(separator: " ")

    guard !observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

    let entry = Entry(observation: observation)
    entry.conversation = engine.conversationMessages
    if let originalText = engine.cachedOriginalEntryText {
      entry.originalEntryText = originalText
    }
    if let summary = engine.conversationSummary {
      entry.conversationSummary = summary
    }

    modelContext.insert(entry)
    do {
      try modelContext.save()
      AppLogger.app.info("Onboarding entry saved: \(entry.id)")
      return entry
    } catch {
      AppLogger.app.error("Failed to save onboarding entry: \(error)")
      return nil
    }
  }
}

// MARK: - Preview

#Preview {
  OnboardingConversationView(name: "Paul", onBack: {}, onContinue: {})
    .environment(\.theme, Theme())
}

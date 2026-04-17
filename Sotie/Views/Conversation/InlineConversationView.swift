import SwiftUI

struct InlineConversationView: View {
  @Binding var messages: [DialogueMessage]
  @Binding var focusedMessageId: UUID?
  @Binding var isStreaming: Bool
  /// When false, user messages render as read-only Text instead of editable TextField.
  var isEditable: Bool = true
  /// When false, the satisfying success-style haptic at the end of a stream
  /// reveal is suppressed. Set this false for synthetic reveals (e.g. prompt
  /// card seed bubbles) where the heavier finish haptic feels out of place.
  var playFinishHaptic: Bool = true
  @FocusState private var focusState: UUID?

  var body: some View {
    // Inter-message vertical air. The per-row vertical padding is left
    // untouched ("sacred") — this only adds extra breathing room between
    // distinct messages so AI bubbles, user replies, and the placeholder
    // don't visually glue together.
    LazyVStack(alignment: .leading, spacing: Spacing.xSmall) {
      ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
        let isLastMessage = index == messages.count - 1

        if message.role == .assistant {
          AIMessageRow(
            message: message,
            isLastMessage: isLastMessage,
            isStreaming: isStreaming,
            playFinishHaptic: playFinishHaptic
          )
        } else {
          if isEditable {
            TextField(
              "",
              text: Binding(
                get: { messages[index].content },
                set: { messages[index].content = $0 }
              ), axis: .vertical
            )
            .typography(.body)
            .themeText(.primary)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.xxSmall)
            .focused($focusState, equals: message.id)
            .accessibilityLabel(appLocalizedString(Localizable.replyToReflection))
          } else {
            Text(message.content)
              .typography(.body)
              .themeText(.primary)
              .padding(.horizontal, Spacing.medium)
              .padding(.vertical, Spacing.xxSmall)
          }
        }
      }
    }
    .onChange(of: focusState) { _, newValue in
      focusedMessageId = newValue
    }
  }
}

// MARK: - AI Message Row

struct AIMessageRow: View {
  let message: DialogueMessage
  let isLastMessage: Bool
  let isStreaming: Bool
  /// When false, suppress the heavier success-style stream-end haptic that
  /// fires by default when streaming flips off. Used by callers that drive
  /// synthetic reveals (e.g. prompt seed bubble) where a finish haptic
  /// would feel like a notification instead of a thoughtful prompt.
  var playFinishHaptic: Bool = true

  @State private var loadingOpacity: Double = 1
  @State private var revealStartDate: Date? = nil
  @State private var streamingEndDate: Date? = nil
  @State private var isRevealing = false
  @State private var cascadeFinishTask: Task<Void, Never>? = nil
  @State private var elapsedAtStreamEnd: Double = 0

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.small) {
      Rectangle()
        .fill(Color.theme.divider)
        .frame(width: 3)

      ZStack(alignment: .leading) {
        // Sparkle stays in view while streaming, hidden via loadingOpacity
        if shouldAnimate {
          AILoadingIndicator()
            .opacity(loadingOpacity)
        }

        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRevealing)) { timeline in
          let elapsed = computeElapsed(at: timeline.date)
          let renderer = BlurRevealRenderer(elapsedTime: elapsed)
          let displayContent = animatedDisplayContent(
            for: message.content,
            elapsed: elapsed,
            renderer: renderer
          )

          Text(displayContent.isEmpty ? " " : displayContent)
            .typography(.body)
            .themeText(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(message.content.isEmpty ? 0 : 1)
            .textRenderer(renderer)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: 20)
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.vertical, Spacing.xxSmall)
    .onAppear {
      if shouldAnimate && message.content.isEmpty {
        loadingOpacity = 1
      } else {
        loadingOpacity = 0
      }
    }
    .onChange(of: message.content) { oldValue, newValue in
      guard animationEnabled else { return }

      if newValue.isEmpty {
        loadingOpacity = 1
        revealStartDate = nil
        streamingEndDate = nil
        isRevealing = false
        elapsedAtStreamEnd = 0
        cascadeFinishTask?.cancel()
        return
      }

      if oldValue.isEmpty && !newValue.isEmpty {
        // Sparkle fades while cascade starts — smooth handoff. The light
        // selection tick at start is a nice "the AI is speaking" cue and
        // is kept for both real and synthetic reveals.
        withAnimation(.easeOut(duration: 0.2)) { loadingOpacity = 0 }
        HapticManager.shared.selection()

        revealStartDate = Date()
        streamingEndDate = nil
        elapsedAtStreamEnd = 0
        isRevealing = true
      }
    }
    .onChange(of: isStreaming) { _, streaming in
      guard !streaming else { return }

      if !isRevealing {
        if isLastMessage && playFinishHaptic {
          HapticManager.shared.streamEnd()
        }
        return
      }

      if isRevealing {
        let endDate = Date()
        elapsedAtStreamEnd = computeElapsed(at: endDate)
        streamingEndDate = endDate

        let renderer = BlurRevealRenderer(elapsedTime: 0)
        let threshold = renderer.revealDuration(
          forCharacterCount: message.content.count
        )
        let remainingRevealTime = max(0.15, (threshold - elapsedAtStreamEnd) / postStreamRevealRate)

        cascadeFinishTask?.cancel()
        cascadeFinishTask = Task { @MainActor in
          try? await Task.sleep(for: .seconds(remainingRevealTime))
          guard !Task.isCancelled else { return }
          isRevealing = false
          if playFinishHaptic {
            HapticManager.shared.streamEnd()
          }
        }
      }
    }
  }

  /// Two-speed cascade:
  /// - While streaming: natural pace just ahead of incoming text.
  /// - After streaming ends: gentle catch-up, so long reflections do not dump
  ///   the remaining tail all at once.
  private func computeElapsed(at date: Date) -> Double {
    guard isRevealing, let start = revealStartDate else { return 100 }

    if let endTime = streamingEndDate {
      let fastPart = date.timeIntervalSince(endTime) * postStreamRevealRate
      return elapsedAtStreamEnd + fastPart
    }

    return date.timeIntervalSince(start) * streamingRevealRate
  }

  private let streamingRevealRate = 1.05
  private let postStreamRevealRate = 1.35
  private let layoutLookaheadCharacters = 0

  private func animatedDisplayContent(
    for content: String,
    elapsed: Double,
    renderer: BlurRevealRenderer
  ) -> String {
    guard shouldAnimateLayout else {
      return content
    }

    let visibleCount = renderer.estimatedVisibleCharacterCount(forElapsedTime: elapsed)
    let prefixCount = min(content.count, visibleCount + layoutLookaheadCharacters)
    let prefix = String(content.prefix(prefixCount))

    // Do not let paragraph separators enter layout before their following text
    // starts revealing; otherwise the quote rule grows by whole blank blocks.
    return prefix.trimmingCharacters(in: .newlines)
  }

  private var shouldAnimate: Bool {
    isLastMessage && isStreaming
  }

  private var animationEnabled: Bool {
    shouldAnimate && !reduceMotion
  }

  private var shouldAnimateLayout: Bool {
    isLastMessage && isRevealing && !reduceMotion
  }
}

struct AILoadingIndicator: View {
  @State private var isAnimating = false

  var body: some View {
    HStack(spacing: Spacing.xSmall) {
      Image(systemName: "sparkles")
        .font(.system(size: 18, weight: .medium))
        .themeText(.secondary)
        .scaleEffect(isAnimating ? 1.15 : 0.85)
        .opacity(isAnimating ? 1.0 : 0.5)
    }
    .frame(height: 20)
    .onAppear {
      withAnimation(
        .easeInOut(duration: 0.8)
          .repeatForever(autoreverses: true)
      ) {
        isAnimating = true
      }
    }
  }
}

#Preview {
  @Previewable @State var messages = [
    DialogueMessage(role: .user, content: "Today I felt really anxious about the presentation."),
    DialogueMessage(
      role: .assistant,
      content:
        "What if this moment was trying to tell you something about what you really need right now?"
    ),
    DialogueMessage(
      role: .user,
      content: "I think I need more time to reflect and less time rushing through things."),
    DialogueMessage(
      role: .assistant, content: "When was the last time you chose reflection over urgency?"),
  ]

  @Previewable @State var focusedMessageId: UUID?
  @Previewable @State var isStreaming = false

  ScrollView {
    InlineConversationView(
      messages: $messages,
      focusedMessageId: $focusedMessageId,
      isStreaming: $isStreaming
    )
    .padding()
  }
  .themeBackground(.primary)
  .environment(\.theme, Theme())
}

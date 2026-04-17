import os
import SwiftUI

/// Full-screen takeaway reveal shown when the user taps "Finish" on a conversation.
/// Uses the same animation language as onboarding: opacity + offset(y:) with easeOut,
/// staggered delays, and consistent typography (26pt bold titles, 22pt semibold status).
struct FinishInsightsView: View {
  let entryText: String
  let messages: [DialogueMessage]
  let onDone: (ConversationInsights) -> Void
  let onSkip: () -> Void

  @State private var phase: Phase = .generating
  @State private var insights: ConversationInsights?
  @State private var errorMessage: String?

  // Reveal animation state
  @State private var titleVisible = false
  @State private var card1Visible = false
  @State private var card2Visible = false
  @State private var card3Visible = false
  @State private var doneButtonVisible = false

  // Blur reveal timing per card
  @State private var card1RevealStart: Date? = nil
  @State private var card2RevealStart: Date? = nil
  @State private var card3RevealStart: Date? = nil
  @State private var card1Revealed = false
  @State private var card2Revealed = false
  @State private var card3Revealed = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private enum Phase: Equatable {
    case generating
    case error
    case revealing
  }

  // Blur reveal speed (slightly slower for readability)
  private let revealSpeed: Double = 1.0

  var body: some View {
    ZStack {
      Color.theme.backgroundPrimary
        .ignoresSafeArea()

      if phase == .generating || phase == .error {
        loadingErrorView
          .transition(.opacity)
      }

      if phase == .revealing {
        revealView
          .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.5), value: phase)
    .task {
      await generateInsights()
    }
  }

  // MARK: - Loading / Error (unified, in-place transitions)

  private var loadingErrorView: some View {
    VStack(spacing: 0) {
      Spacer()

      // Icon: sparkle (generating) or warning (error)
      ZStack {
        if phase == .generating {
          SparkleLoadingIndicator()
            .transition(.opacity)
        }

        if phase == .error {
          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 56, weight: .light))
            .themeText(.secondary)
            .transition(.opacity)
        }
      }
      .animation(.easeInOut(duration: 0.4), value: phase)

      Spacer().frame(height: 32)

      // Text: status (generating) or error + buttons
      ZStack {
        if phase == .generating {
          Text(appLocalizedString(Localizable.insightsGenerating))
            .font(.system(size: 22, weight: .semibold))
            .themeText(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.large)
            .transition(.asymmetric(
              insertion: .opacity.combined(with: .offset(y: 8)),
              removal: .opacity.combined(with: .offset(y: -8))
            ))
        }

        if phase == .error {
          VStack(spacing: Spacing.large) {
            Text(errorMessage ?? appLocalizedString(Localizable.insightsError))
              .font(.system(size: 22, weight: .semibold))
              .themeText(.primary)
              .multilineTextAlignment(.center)
              .padding(.horizontal, Spacing.large)

            VStack(spacing: Spacing.small) {
              Button {
                HapticManager.shared.light()
                withAnimation(.easeInOut(duration: 0.4)) {
                  phase = .generating
                }
                Task { await generateInsights() }
              } label: {
                Text(appLocalizedString(Localizable.insightsRetry))
                  .font(.system(size: 17, weight: .semibold))
              }
              .buttonStyle(.glassProminent)
              .tint(Color.theme.buttonBackground)

              Button {
                HapticManager.shared.soft()
                Analytics.insightsSkipped()
                onSkip()
              } label: {
                Text(appLocalizedString(Localizable.insightsSkip))
                  .font(.system(size: 17, weight: .regular))
                  .themeText(.tertiary)
              }
              .buttonStyle(.plain)
            }
          }
          .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .offset(y: -8))
          ))
        }
      }
      .animation(.easeInOut(duration: 0.4), value: phase)

      Spacer()
    }
  }

  // MARK: - Reveal State

  private var revealView: some View {
    VStack(spacing: 0) {
      Spacer().frame(height: 60)

      // Title — 26pt bold, centered, fades in first
      Text(appLocalizedString(Localizable.insightsTitle))
        .font(.system(size: 26, weight: .bold))
        .themeText(.primary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, Spacing.large)
        .opacity(titleVisible ? 1 : 0)
        .offset(y: titleVisible ? 0 : 8)

      Spacer().frame(height: 24)

      // Scrollable cards — always in tree, animated via opacity+offset
      if let insights {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: allCardsRevealed)) { timeline in
          ScrollView {
            VStack(alignment: .leading, spacing: 16) {
              insightCard(
                icon: "doc.text",
                title: appLocalizedString(Localizable.insightsWhatHappened),
                content: insights.whatHappened,
                revealStart: card1RevealStart,
                isRevealed: $card1Revealed,
                at: timeline.date
              )
              .opacity(card1Visible ? 1 : 0)
              .offset(y: card1Visible ? 0 : 12)

              insightCard(
                icon: "eye",
                title: appLocalizedString(Localizable.insightsWhatsUnderneath),
                content: insights.whatsUnderneath,
                revealStart: card2RevealStart,
                isRevealed: $card2Revealed,
                at: timeline.date
              )
              .opacity(card2Visible ? 1 : 0)
              .offset(y: card2Visible ? 0 : 12)

              insightCard(
                icon: "arrow.right.circle",
                title: appLocalizedString(Localizable.insightsWhatMattersNow),
                content: insights.whatMattersNow,
                revealStart: card3RevealStart,
                isRevealed: $card3Revealed,
                at: timeline.date
              )
              .opacity(card3Visible ? 1 : 0)
              .offset(y: card3Visible ? 0 : 12)

              Spacer().frame(height: 80)
            }
            .padding(.horizontal, Spacing.large)
          }
        }
      }

      Spacer(minLength: 0)

      // Pinned Done button at bottom
      Button {
        HapticManager.shared.success()
        if let insights {
          onDone(insights)
        } else {
          onSkip()
        }
      } label: {
        Text(appLocalizedString(Localizable.insightsDone))
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Color.theme.buttonText)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.small)
      }
      .buttonStyle(.glassProminent)
      .tint(Color.theme.buttonBackground)
      .padding(.horizontal, Spacing.large)
      .padding(.bottom, Spacing.large)
      .opacity(doneButtonVisible ? 1 : 0)
      .offset(y: doneButtonVisible ? 0 : 12)
    }
  }

  private var allCardsRevealed: Bool {
    card1Revealed && card2Revealed && card3Revealed
  }

  // MARK: - Insight Card with Blur Reveal

  private func insightCard(
    icon: String,
    title: String,
    content: String,
    revealStart: Date?,
    isRevealed: Binding<Bool>,
    at currentDate: Date
  ) -> some View {
    let elapsed: Double = {
      guard let start = revealStart else { return 0 }
      return currentDate.timeIntervalSince(start) * revealSpeed
    }()

    let renderer = BlurRevealRenderer(elapsedTime: elapsed)

    // Check if this card's text is fully revealed
    let threshold = renderer.revealDuration(forCharacterCount: content.count)
    if elapsed >= threshold && !isRevealed.wrappedValue {
      DispatchQueue.main.async { isRevealed.wrappedValue = true }
    }

    return VStack(alignment: .leading, spacing: Spacing.small) {
      HStack(spacing: Spacing.xSmall) {
        Image(systemName: icon)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Color.theme.accentPrimary)

        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.theme.accentPrimary)
          .textCase(.uppercase)
      }

      Text(content)
        .typography(.body)
        .themeText(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .textRenderer(renderer)
    }
    .padding(Spacing.medium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.theme.backgroundSecondary)
    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium))
  }

  // MARK: - Staggered Reveal (DispatchQueue-based, immune to Task cancellation)

  @MainActor
  private func revealCardsSequentially() async {
    let fast = reduceMotion

    let titleDelay: Double = fast ? 0.05 : 0.2
    let titleToFirstCard: Double = fast ? 0.1 : 0.5
    let cardInterval: Double = fast ? 0.2 : 1.2
    let doneDelay: Double = fast ? 0.15 : 0.6

    DispatchQueue.main.asyncAfter(deadline: .now() + titleDelay) {
      withAnimation(.easeOut(duration: 0.6)) { titleVisible = true }
      HapticManager.shared.medium()
    }

    let firstCardTime = titleDelay + titleToFirstCard
    DispatchQueue.main.asyncAfter(deadline: .now() + firstCardTime) {
      withAnimation(.easeOut(duration: 0.5)) { card1Visible = true }
      card1RevealStart = Date()
      HapticManager.shared.light()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + firstCardTime + cardInterval) {
      withAnimation(.easeOut(duration: 0.5)) { card2Visible = true }
      card2RevealStart = Date()
      HapticManager.shared.light()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + firstCardTime + cardInterval * 2) {
      withAnimation(.easeOut(duration: 0.5)) { card3Visible = true }
      card3RevealStart = Date()
      HapticManager.shared.light()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + firstCardTime + cardInterval * 2 + doneDelay) {
      withAnimation(.easeOut(duration: 0.5)) { doneButtonVisible = true }
      HapticManager.shared.success()
    }
  }

  // MARK: - Generation Logic

  private func generateInsights() async {
    errorMessage = nil

    let startTime = CFAbsoluteTimeGetCurrent()
    Analytics.insightsRequested(messageCount: messages.count)

    do {
      let result = try await DefaultAIService.shared.generateInsights(
        entryText: entryText,
        messages: messages
      )

      let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
      Analytics.insightsGenerated(messageCount: messages.count, latencyMs: latencyMs)

      insights = result

      // Swap phase — no animated wrapper, children animate themselves
      phase = .revealing

      // Staggered reveal — use a detached continuation so the phase swap
      // doesn't cancel our sleep chain (view body re-evaluation can cancel
      // the .task closure's Task when the conditional branch changes).
      await revealCardsSequentially()

    } catch is CancellationError {
      // View disappeared — no-op
    } catch {
      withAnimation(.easeInOut(duration: 0.4)) {
        phase = .error
      }
      errorMessage = userFacingAIError(from: error).message
      Analytics.insightsFailed(reason: String(describing: type(of: error)))
      AppLogger.ai.error("Insights generation failed: \(error)")
    }
  }
}

// MARK: - Sparkle Loading Indicator (matches AILoadingIndicator scale/opacity pulse)

private struct SparkleLoadingIndicator: View {
  @State private var isAnimating = false

  var body: some View {
    Image(systemName: "sparkles")
      .font(.system(size: 56, weight: .light))
      .themeText(.primary)
      .scaleEffect(isAnimating ? 1.15 : 0.85)
      .opacity(isAnimating ? 1.0 : 0.6)
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
  FinishInsightsView(
    entryText: "I keep thinking about what happened at work today",
    messages: [
      DialogueMessage(role: .user, content: "I keep thinking about what happened at work today"),
      DialogueMessage(role: .assistant, content: "What keeps coming back?"),
      DialogueMessage(role: .user, content: "My manager said I wasn't ready for the project"),
      DialogueMessage(role: .assistant, content: "What part of that landed hardest?"),
      DialogueMessage(role: .user, content: "That maybe she's right and I'm not good enough"),
    ],
    onDone: { _ in },
    onSkip: {}
  )
  .environment(\.theme, Theme())
}

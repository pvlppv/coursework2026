//
//  DemoCompleteView.swift
//  Sotie
//
//  Screen 24: "congratulations! you've started your first reflection"
//  Shows the actual entry card (from the conversation just completed)
//  to preview what their reflections will look like in the journal.
//  Tap Continue to finish onboarding.
//

import SwiftUI
import SwiftData

struct DemoCompleteView: View {
    let onContinue: () -> Void
    @Environment(\.modelContext) private var modelContext

    @State private var titleVisible = false
    @State private var subtitleVisible = false
    @State private var cardVisible = false
    @State private var messageVisible = false
    @State private var buttonVisible = false

    // Loaded from the saved onboarding entry
    @State private var firstUserMessage: String = ""
    @State private var lastAIResponse: String = ""
    @State private var entryDate: Date = Date()

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 100)

                // Title: "congratulations!"
                Text(appLocalizedString(Localizable.onboardingFlowDemoCompleteTitle))
                    .font(.system(size: 28, weight: .bold))
                    .themeText(.primary)
                    .multilineTextAlignment(.center)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 8)

                Spacer().frame(height: 12)

                // Subtitle: "you've started your first reflection"
                Text(appLocalizedString(Localizable.onboardingFlowDemoCompleteSubtitle))
                    .font(.system(size: 20, weight: .semibold))
                    .themeText(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(subtitleVisible ? 1 : 0)
                    .offset(y: subtitleVisible ? 0 : 8)

                Spacer().frame(height: 40)

                // Entry card with actual conversation text
                entryCard
                    .opacity(cardVisible ? 1 : 0)
                    .scaleEffect(cardVisible ? 1 : 0.96)

                Spacer().frame(height: 32)

                // Message: "your reflections will be saved..."
                Text(appLocalizedString(Localizable.onboardingFlowDemoCompleteMessage))
                    .font(.system(size: 17, weight: .medium))
                    .themeText(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.large)
                    .opacity(messageVisible ? 1 : 0)
                    .offset(y: messageVisible ? 0 : 8)

                Spacer()

                // Continue button
                OnboardingPrimaryButton(
                    appLocalizedString(Localizable.onboardingFlowContinue),
                    action: { onContinue() }
                )
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.xLarge)
                .opacity(buttonVisible ? 1 : 0)
                .offset(y: buttonVisible ? 0 : 12)
            }
        }
        .onAppear {
            HapticManager.shared.success()
            loadOnboardingEntry()
            startAnimations()
        }
    }

    // MARK: - Entry Card (actual conversation text)

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            // Header with date
            HStack(spacing: Spacing.xSmall) {
                Text(DateFormatter.formatDateTimeForCard(entryDate))
                    .typography(.caption)
                    .themeText(.tertiary)
                Spacer()
            }

            // First user message
            if !firstUserMessage.isEmpty {
                Text(firstUserMessage)
                    .typography(.body)
                    .themeText(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            // Last AI response with "..." pinned
            if !lastAIResponse.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .themeText(.secondary)
                    Text(lastAIResponse + "...")
                        .typography(.caption)
                        .themeText(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.theme.backgroundSecondary)
        )
        .padding(.horizontal, Spacing.large)
    }

    // MARK: - Load Entry

    /// Loads the most recent entry (the one saved by the demo conversation).
    private func loadOnboardingEntry() {
        var descriptor = FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let entry = try? modelContext.fetch(descriptor).first {
            entryDate = entry.date
            // Use conversation first user message if available
            if let firstUser = entry.conversation.first(where: { $0.role == .user }) {
                firstUserMessage = firstUser.content
            } else {
                firstUserMessage = entry.observation
            }
            // Last AI response
            if let lastAI = entry.conversation.last(where: { $0.role == .assistant }) {
                lastAIResponse = lastAI.content
            }
        }
    }

    // MARK: - Animation Sequencing

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.7).delay(0.3)) {
            titleVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(0.7)) {
            subtitleVisible = true
        }
        withAnimation(.easeOut(duration: 0.7).delay(1.2)) {
            cardVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(1.8)) {
            messageVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(2.3)) {
            buttonVisible = true
        }
    }
}

#Preview {
    DemoCompleteView(onContinue: {})
        .environment(\.theme, Theme())
}

import SwiftUI

// MARK: - Helper Functions

private func formatDateTimeForCard(_ date: Date) -> String {
  return DateFormatter.formatDateTimeForCard(date)
}

private func formatNumericValue(_ value: Double) -> String {
  // Check if the number is a whole number
  if value.truncatingRemainder(dividingBy: 1) == 0 {
    return String(format: "%.0f", value)
  } else {
    return String(format: "%.1f", value)
  }
}

// MARK: - Entry Card Container

struct EntryCard: View {
  let entry: Entry
  let onTap: () -> Void


  var body: some View {
    Button(action: {
      HapticManager.shared.light()
      onTap()
    }) {
      cardContent
        .contentShape(Rectangle())
    }
    .buttonStyle(PlainButtonStyle())
  }

  @ViewBuilder
  private var cardContent: some View {
    NoteEntryCard(
      entry: entry
    )
  }
}

// MARK: - Note Entry Card

struct NoteEntryCard: View {
  let entry: Entry


  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      // Header with date, time, and notification indicator
      HStack(spacing: Spacing.xSmall) {
        // Notification dot indicator
        if entry.hasActiveNotification {
          Circle()
            .fill(Color.theme.textPrimary)
            .frame(width: 6, height: 6)
        }

        Text(formatDateTimeForCard(entry.date))
          .typography(.caption)
          .themeText(.tertiary)

        Spacer()

        if entry.comment != nil {
          Image(systemName: "text.bubble")
            .font(.caption)
            .themeText(.tertiary)
        }
      }

      // Content — use decoded conversation, not persisted flag,
      // to avoid showing empty card when conversationJSON is corrupt
      if !entry.conversation.isEmpty {
        Text(entry.conversation.first?.content ?? "")
          .typography(.body)
          .themeText(.primary)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
      } else if !entry.observation.isEmpty {
        Text(entry.observation)
          .typography(.body)
          .themeText(.primary)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
      }

      // Last AI response
      if let lastResponse = entry.lastAIResponse {
        HStack(alignment: .top, spacing: 4) {
          Image(systemName: "sparkles")
            .font(.system(size: 11))
            .themeText(.secondary)
          Text(lastResponse)
            .typography(.caption)
            .themeText(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
      }
    }
    .padding(Spacing.medium)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Preview

#Preview {
  @Previewable @State var selectedPhoto: String? = nil
  @Previewable @State var showingPhoto: Bool = false

  VStack(spacing: Spacing.medium) {
    NoteEntryCard(
      entry: Entry(
        observation: "Feeling great today! Had a wonderful morning walk and coffee with friends.",
        comment: "Really enjoyed the fresh air",
        date: Date()
      )
    )
  }
  .padding()
  .background(Color.theme.backgroundPrimary)
  .environment(\.theme, Theme())
  .environmentObject(LanguageManager.shared)
}

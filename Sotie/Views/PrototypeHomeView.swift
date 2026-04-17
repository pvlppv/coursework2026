import SwiftUI

struct PrototypeHomeView: View {
  @State private var showFAB = true
  @State private var showingAIDetail = false

  // Mock data
  private let entries = MockData.entries
  private let aiInsight = MockData.aiInsight

  var body: some View {
    NavigationStack {
      ZStack(alignment: .bottomTrailing) {
        // Main content
        ScrollView {
          LazyVStack(spacing: 0) {
            // Custom header
            customHeader
              .padding(.horizontal, Spacing.medium)
              .padding(.top, Spacing.medium)

            // AI Analysis section
            aiAnalysisSection
              .padding(.horizontal, Spacing.medium)
              .padding(.top, Spacing.medium)

            // Timeline entries section
            timelineSection
              .padding(.horizontal, Spacing.medium)
              .padding(.top, Spacing.medium)
          }
          .padding(.bottom, 100)  // Extra bottom padding for FAB
        }
        .scrollIndicators(.hidden)
        .themeBackground(.primary)
        .refreshable {
          // Mock refresh
          try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // Floating Action Button
        if showFAB {
          floatingActionButton
            .padding(.trailing, Spacing.medium)
            .padding(.bottom, Spacing.large)
            .transition(.scale.combined(with: .opacity))
        }
      }
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  // MARK: - Custom Header
  private var customHeader: some View {
    VStack(spacing: 0) {
      // Header content
      HStack {
        Button(action: {
          // Navigate to streak
          HapticManager.shared.light()
        }) {
          Image(systemName: "flame.circle")
            .font(.title2)
            .foregroundColor(Color.theme.textSecondary)
        }

        Spacer()

        Button(action: {
          // Navigate to profile
          HapticManager.shared.light()
        }) {
          Image(systemName: "person.circle")
            .font(.title2)
            .foregroundColor(Color.theme.textSecondary)
        }
      }
    }
  }

  // MARK: - AI Analysis Section
  private var aiAnalysisSection: some View {
    Button(action: {
      HapticManager.shared.light()
      showingAIDetail = true
    }) {
      VStack(alignment: .leading, spacing: Spacing.small) {
        // Header
        HStack {
          Image(systemName: "brain.head.profile")
            .foregroundColor(Color.theme.textPrimary)
            .font(.title3)

          Text(appLocalizedString(Localizable.aiAnalysis))
            .typography(.subheadline)
            .themeText(.primary)
            .fontWeight(.medium)

          Spacer()

          Image(systemName: "arrow.right")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(Color.theme.accentPrimary)
        }

        // Content
        Text(appLocalizedString(Localizable.discoverPatterns))
          .typography(.body)
          .themeText(.secondary)
          .multilineTextAlignment(.leading)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.medium)
      .background(
        RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
          .fill(Color.theme.backgroundSecondary)
          .themeShadow(.large)
      )
    }
    .buttonStyle(PlainButtonStyle())
    .sheet(isPresented: $showingAIDetail) {
      AIDetailView()
    }
  }

  // MARK: - Timeline Section
  private var timelineSection: some View {
    VStack(spacing: 0) {
      if filteredEntries.isEmpty {
        emptyState
      } else {
        LazyVStack(spacing: Spacing.large) {
          ForEach(groupedEntries, id: \.date) { groupInfo in
            VStack(spacing: Spacing.small) {
              // Date group headline
              dateGroupHeadline(groupInfo.title)

              // Entries for this group
              VStack(spacing: 0) {
                ForEach(groupInfo.entries, id: \.id) { mockEntry in
                  PrototypeEntryCard(
                    mockEntry: mockEntry,
                    onTap: {
                      // Navigate to entry detail
                      HapticManager.shared.light()
                    },
                    onEdit: {
                      // Edit entry
                      HapticManager.shared.light()
                    }
                  )

                  if mockEntry.id != groupInfo.entries.last?.id {
                    Divider()
                      .background(Color.theme.divider)
                      .padding(.horizontal, Spacing.medium)
                  }
                }
              }
              .background(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                  .fill(Color.theme.backgroundSecondary)
                  .shadow(color: Color.theme.shadow.opacity(0.08), radius: 4, x: 0, y: 2)
              )
            }
            .id(groupInfo.date)
          }
        }
        .padding(.vertical, Spacing.small)
      }
    }
  }

  // MARK: - Floating Action Button
  private var floatingActionButton: some View {
    Button(action: {
      HapticManager.shared.medium()
      // Add new entry
    }) {
      Image(systemName: "plus")
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundColor(Color.theme.buttonText)
        .frame(width: 60, height: 60)
        .background(
          Circle()
            .fill(Color.theme.buttonBackground)
            .themeShadow(.elevated)
        )
    }
    .buttonStyle(PlainButtonStyle())
    .accessibilityLabel(appLocalizedString(Localizable.addEntry))
  }

  // MARK: - Computed Properties
  private var filteredEntries: [MockEntry] {
    return entries
  }

  private var groupedEntries: [MockDateGroupInfo] {
    let calendar = LanguageManager.shared.calendar
    let now = Date()

    var groups: [MockDateGroupInfo] = []

    // Today
    let todayEntries = filteredEntries.filter { entry in
      calendar.isDate(entry.date, inSameDayAs: now)
    }
    if !todayEntries.isEmpty {
      groups.append(
        MockDateGroupInfo(
          group: .today,
          title: appLocalizedString(Localizable.today),
          entries: todayEntries.sorted { $0.date > $1.date },
          date: now
        ))
    }

    // Yesterday
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
    let yesterdayEntries = filteredEntries.filter { entry in
      calendar.isDate(entry.date, inSameDayAs: yesterday)
    }
    if !yesterdayEntries.isEmpty {
      groups.append(
        MockDateGroupInfo(
          group: .yesterday,
          title: appLocalizedString(Localizable.yesterday),
          entries: yesterdayEntries.sorted { $0.date > $1.date },
          date: yesterday
        ))
    }

    // This Week
    let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    let thisWeekEntries = filteredEntries.filter { entry in
      entry.date >= startOfWeek && !calendar.isDate(entry.date, inSameDayAs: now)
        && !calendar.isDate(entry.date, inSameDayAs: yesterday)
    }
    if !thisWeekEntries.isEmpty {
      groups.append(
        MockDateGroupInfo(
          group: .thisWeek,
          title: appLocalizedString(Localizable.thisWeek),
          entries: thisWeekEntries.sorted { $0.date > $1.date },
          date: startOfWeek
        ))
    }

    // Last Week
    let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfWeek) ?? now
    let lastWeekEnd = startOfWeek
    let lastWeekEntries = filteredEntries.filter { entry in
      entry.date >= lastWeekStart && entry.date < lastWeekEnd
    }
    if !lastWeekEntries.isEmpty {
      groups.append(
        MockDateGroupInfo(
          group: .lastWeek,
          title: appLocalizedString(Localizable.lastWeek),
          entries: lastWeekEntries.sorted { $0.date > $1.date },
          date: lastWeekStart
        ))
    }

    return groups
  }

  private func dateGroupHeadline(_ title: String) -> some View {
    HStack {
      Text(title)
        .typography(.title2)
        .themeText(.primary)
        .fontWeight(.bold)

      Spacer()
    }
    .padding(.horizontal, 0)
  }

  private var emptyState: some View {
    EmptyStateView(
      icon: "doc.text",
      title: LocalizedStringKey(Localizable.noEntriesYet),
      description: LocalizedStringKey(Localizable.tapPlusToAddFirstEntry)
    )
  }
}

// MARK: - Mock Data

struct MockData {

  static let aiInsight =
    "Your mood tends to improve by 23% on days when you exercise for at least 30 minutes. Consider scheduling workouts on challenging days."

  static let entries: [MockEntry] = [
    // Mood entries
    MockEntry(
      id: UUID(),
      observation:
        "Feeling really energized today! Had a great morning workout and the weather is perfect.",
      date: Date().addingTimeInterval(-3600),  // 1 hour ago
      aiMessage: "You only feel good after working out"
    ),
    MockEntry(
      id: UUID(),
      observation: "Stressed about work presentation tomorrow",
      date: Date().addingTimeInterval(-7200),  // 2 hours ago
      aiMessage: nil
    ),
    MockEntry(
      id: UUID(),
      observation: "8.5",
      date: Date().addingTimeInterval(-10800),  // 3 hours ago
      extractedValue: 8.5,
      aiMessage: "Your best day this week"
    ),

    // Health entries
    MockEntry(
      id: UUID(),
      observation: "7.5 hours",
      date: Date().addingTimeInterval(-86400),  // 1 day ago
      extractedValue: 7.5,
      aiMessage: "7.5 hours is your sweet spot"
    ),
    MockEntry(
      id: UUID(),
      observation: "Headache",
      date: Date().addingTimeInterval(-172800),  // 2 days ago
      aiMessage: "Screen time = headache"
    ),
    MockEntry(
      id: UUID(),
      observation: "30 minutes cardio",
      date: Date().addingTimeInterval(-259200),  // 3 days ago
      aiMessage: "You're on a roll",
      mediaType: .photo
    ),

    // Lifestyle entries
    MockEntry(
      id: UUID(),
      observation: "Coffee with Sarah",
      date: Date().addingTimeInterval(-43200),  // 12 hours ago
      aiMessage: "Friends give you energy",
      mediaType: .video
    ),
    MockEntry(
      id: UUID(),
      observation: "2",
      date: Date().addingTimeInterval(-129600),  // 1.5 days ago
      extractedValue: 2.0,
      aiMessage: nil
    ),
    MockEntry(
      id: UUID(),
      observation: "Pizza",
      date: Date().addingTimeInterval(-216000),  // 2.5 days ago
      aiMessage: nil
    ),

    // Productivity entries
    MockEntry(
      id: UUID(),
      observation: "Completed project proposal",
      date: Date().addingTimeInterval(-86400),  // 1 day ago
      aiMessage: "Task completion streak",
      mediaType: .voice
    ),
    MockEntry(
      id: UUID(),
      observation: "6",
      date: Date().addingTimeInterval(-172800),  // 2 days ago
      extractedValue: 6.0,
      aiMessage: "Peak productivity hours"
    ),
    MockEntry(
      id: UUID(),
      observation: "Procrastinated on emails",
      date: Date().addingTimeInterval(-259200),  // 3 days ago
      aiMessage: "Email avoidance pattern"
    ),

    // More entries for variety
    MockEntry(
      id: UUID(),
      observation: "Meditation session",
      date: Date().addingTimeInterval(-345600),  // 4 days ago
      aiMessage: nil,
      mediaType: .voice
    ),
    MockEntry(
      id: UUID(),
      observation: "9.2",
      date: Date().addingTimeInterval(-432000),  // 5 days ago
      extractedValue: 9.2,
      aiMessage: "Exceptional sleep quality"
    ),
    MockEntry(
      id: UUID(),
      observation: "Read 50 pages",
      date: Date().addingTimeInterval(-518400),  // 6 days ago
      aiMessage: nil,
      mediaType: .photo
    ),

    // Additional entries with different types
    MockEntry(
      id: UUID(),
      observation: "Excellent",
      date: Date().addingTimeInterval(-604800),  // 7 days ago
      aiMessage: nil
    ),
    MockEntry(
      id: UUID(),
      observation: "Voice note about weekend plans",
      date: Date().addingTimeInterval(-691200),  // 8 days ago
      aiMessage: nil,
      mediaType: .voice
    ),
    MockEntry(
      id: UUID(),
      observation: "Sunset photos from the beach",
      date: Date().addingTimeInterval(-777600),  // 9 days ago
      aiMessage: nil,
      mediaType: .photo
    ),
    MockEntry(
      id: UUID(),
      observation: "4.5",
      date: Date().addingTimeInterval(-864000),  // 10 days ago
      extractedValue: 4.5,
      aiMessage: nil
    ),
    MockEntry(
      id: UUID(),
      observation: "Gym workout",
      date: Date().addingTimeInterval(-950400),  // 11 days ago
      aiMessage: "Strength training session",
      mediaType: .video
    ),
    MockEntry(
      id: UUID(),
      observation: "Good",
      date: Date().addingTimeInterval(-1_036_800),  // 12 days ago
      aiMessage: nil
    ),
    MockEntry(
      id: UUID(),
      observation: "Completed 3 tasks",
      date: Date().addingTimeInterval(-1_123_200),  // 13 days ago
      aiMessage: "Task completion pattern",
      mediaType: .voice
    ),
  ]
}

// MARK: - Mock Date Group Info

struct MockDateGroupInfo {
  let group: DateGroup
  let title: String
  let entries: [MockEntry]
  let date: Date
}

// MARK: - Mock Entry Model

struct MockEntry: Identifiable {
  let id: UUID
  let observation: String
  let date: Date
  let extractedValue: Double?
  let aiMessage: String?
  let mediaType: MediaType?

  enum MediaType {
    case photo
    case video
    case voice
  }

  init(
    id: UUID,
    observation: String,
    date: Date,
    extractedValue: Double? = nil,
    aiMessage: String? = nil,
    mediaType: MediaType? = nil
  ) {
    self.id = id
    self.observation = observation
    self.date = date
    self.extractedValue = extractedValue
    self.aiMessage = aiMessage
    self.mediaType = mediaType
  }

  // Convert MockEntry to Entry for compatibility with EntryCard
  func toEntry() -> Entry {
    let entry = Entry(
      observation: observation,
      date: date,
      extractedValue: extractedValue
    )
    entry.id = id
    return entry
  }
}

// MARK: - Preview

// MARK: - Prototype Entry Card

struct PrototypeEntryCard: View {
  let mockEntry: MockEntry
  let onTap: () -> Void
  let onEdit: () -> Void

  private func formatDateTimeForCard(_ date: Date) -> String {
    return DateFormatter.formatDateTimeForCard(date)
  }

  var body: some View {
    Button(action: {
      HapticManager.shared.light()
      onTap()
    }) {
      VStack(alignment: .leading, spacing: Spacing.small) {
        // Header with date
        HStack {
          Text(formatDateTimeForCard(mockEntry.date))
            .typography(.caption)
            .themeText(.tertiary)

          Spacer()
        }

        // Content
        if !mockEntry.observation.isEmpty {
          Text(mockEntry.observation)
            .typography(.body)
            .themeText(.primary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
        }

        // Media thumbnails
        if let mediaType = mockEntry.mediaType {
          mediaThumbnails(mediaType)
        }

        // AI Message
        if let aiMessage = mockEntry.aiMessage {
          HStack(spacing: Spacing.xSmall) {
            aiMessageIcon(aiMessage)

            Text(aiMessage)
              .typography(.caption)
              .fontWeight(.medium)
              .foregroundColor(aiMessageColor(aiMessage))

            Spacer()
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.medium)
    }
    .buttonStyle(PlainButtonStyle())
  }

  private func mediaThumbnails(_ mediaType: MockEntry.MediaType) -> some View {
    HStack(spacing: Spacing.xSmall) {
      ForEach(0..<3, id: \.self) { _ in
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.theme.backgroundTertiary)
          .frame(width: 40, height: 40)
          .overlay(
            Group {
              switch mediaType {
              case .photo:
                Image(systemName: "photo")
                  .font(.caption)
                  .themeText(.tertiary)
              case .video:
                Image(systemName: "play.fill")
                  .font(.caption)
                  .themeText(.tertiary)
              case .voice:
                Image(systemName: "waveform")
                  .font(.caption)
                  .themeText(.tertiary)
              }
            }
          )
      }
    }
  }

  private func aiMessageIcon(_ message: String) -> some View {
    Group {
      if message.contains("correlation") || message.contains("connection")
        || message.contains("boost") || message.contains("feel good")
      {
        Image(systemName: "link.circle")
          .font(.caption2)
          .foregroundColor(aiMessageColor(message))
      } else if message.contains("anomaly") || message.contains("headache")
        || message.contains("screen")
      {
        Image(systemName: "exclamationmark.triangle")
          .font(.caption2)
          .foregroundColor(aiMessageColor(message))
      } else if message.contains("trend") || message.contains("streak")
        || message.contains("maintained") || message.contains("pattern")
        || message.contains("sweet spot")
      {
        Image(systemName: "chart.line.uptrend.xyaxis")
          .font(.caption2)
          .foregroundColor(aiMessageColor(message))
      } else {
        Image(systemName: "link.circle")
          .font(.caption2)
          .foregroundColor(aiMessageColor(message))
      }
    }
  }

  private func aiMessageColor(_ message: String) -> Color {
    return Color.theme.textPrimary
  }

  private func aiMessageBackgroundColor(_ message: String) -> Color {
    return Color.theme.backgroundTertiary
  }
}

// MARK: - AI Detail View

struct AIDetailView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.large) {
          // Header
          VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
              Image(systemName: "brain.head.profile")
                .font(.title)
                .foregroundColor(Color.theme.textPrimary)

              Text(appLocalizedString(Localizable.aiAnalysis))
                .typography(.title)
                .themeText(.primary)
                .fontWeight(.bold)
            }

            Text(appLocalizedString(Localizable.discoverPatternsAndInsights))
              .typography(.body)
              .themeText(.secondary)
          }
          .padding(Spacing.medium)
          .background(
            RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
              .fill(Color.theme.backgroundSecondary)
              .themeShadow(.medium)
          )

          // Sample insights
          VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(appLocalizedString(Localizable.recentInsights))
              .typography(.headline)
              .themeText(.primary)

            VStack(spacing: Spacing.small) {
              insightCard(
                title: "Workout = mood boost",
                description:
                  "Every time you work out, your mood jumps. You're not exercising for health - you're doing it because you feel like shit without it.",
                confidence: "High",
                icon: "link.circle",
                color: .blue
              )

              insightCard(
                title: "Screen time = headache",
                description:
                  "You know this already. 6+ hours of screen time and you're guaranteed a headache. Your body is telling you to stop.",
                confidence: "High",
                icon: "exclamationmark.triangle",
                color: .orange
              )

              insightCard(
                title: "Friends give you energy",
                description:
                  "Every coffee meeting, every social interaction - your mood spikes. You're not an introvert, you're just not getting enough social time.",
                confidence: "Medium",
                icon: "link.circle",
                color: .blue
              )

              insightCard(
                title: "7.5 hours is your sweet spot",
                description:
                  "You've found your magic number. Less than 7.5 hours and you're dragging. More than 7.5 hours and you're groggy. Stop fighting it.",
                confidence: "High",
                icon: "chart.line.uptrend.xyaxis",
                color: .green
              )

              insightCard(
                title: "You're a morning person",
                description:
                  "9-11 AM is when you get shit done. Everything else is just pretending to work. Stop scheduling important stuff in the afternoon.",
                confidence: "High",
                icon: "chart.line.uptrend.xyaxis",
                color: .green
              )

              insightCard(
                title: "You stress-eat and stress-procrastinate",
                description:
                  "Work gets hard, you avoid emails, work gets harder. You're stuck in a loop. The only way out is to break the cycle.",
                confidence: "Medium",
                icon: "exclamationmark.triangle",
                color: .orange
              )
            }
          }
        }
        .padding(Spacing.medium)
      }
      .themeBackground(.primary)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(appLocalizedString(Localizable.done)) {
            dismiss()
          }
          .foregroundColor(Color.theme.textPrimary)
        }
      }
    }
  }

  private func insightCard(
    title: String, description: String, confidence: String, icon: String, color: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      HStack {
        HStack(spacing: Spacing.xSmall) {
          Image(systemName: icon)
            .font(.caption)
            .foregroundColor(color)

          Text(title)
            .typography(.subheadline)
            .themeText(.primary)
            .fontWeight(.semibold)
        }

        Spacer()

        Text(confidence)
          .typography(.caption)
          .fontWeight(.medium)
          .foregroundColor(color)
          .padding(.horizontal, Spacing.small)
          .padding(.vertical, 4)
          .background(
            Capsule()
              .fill(color.opacity(0.1))
          )
      }

      Text(description)
        .typography(.body)
        .themeText(.secondary)
        .multilineTextAlignment(.leading)
    }
    .padding(Spacing.medium)
    .background(
      RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
        .fill(Color.theme.backgroundSecondary)
        .themeShadow(.subtle)
    )
  }
}

#Preview {
  PrototypeHomeView()
    .environment(\.theme, Theme())
}

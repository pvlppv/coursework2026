import Foundation

struct StatisticsCalculator {

  @MainActor
  static func currentStreak(
    from entries: [Entry],
    calendar: Calendar? = nil,
    referenceDate: Date = Date()
  ) -> Int {
    let resolvedCalendar = calendar ?? LanguageManager.shared.calendar
    return currentStreak(
      from: uniqueEntryDays(from: entries, calendar: resolvedCalendar),
      calendar: resolvedCalendar,
      referenceDate: referenceDate
    )
  }

  @MainActor
  static func currentStreak(
    from activeDays: Set<Date>,
    calendar: Calendar? = nil,
    referenceDate: Date = Date()
  ) -> Int {
    let calendar = calendar ?? LanguageManager.shared.calendar
    guard !activeDays.isEmpty else { return 0 }

    let today = calendar.startOfDay(for: referenceDate)
    guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
      return 0
    }

    guard activeDays.contains(today) || activeDays.contains(yesterday) else {
      return 0
    }

    var streak = 0
    var date = activeDays.contains(today) ? today : yesterday

    while activeDays.contains(date) {
      streak += 1
      guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else {
        break
      }
      date = previousDay
    }

    return streak
  }

  @MainActor
  static func bestStreak(
    from activeDays: Set<Date>,
    calendar: Calendar? = nil
  ) -> Int {
    let calendar = calendar ?? LanguageManager.shared.calendar
    let sortedDays = activeDays.sorted()
    guard let firstDay = sortedDays.first else { return 0 }

    var best = 1
    var streak = 1
    var previousDay = firstDay

    for currentDay in sortedDays.dropFirst() {
      guard let nextExpectedDay = calendar.date(byAdding: .day, value: 1, to: previousDay) else {
        streak = 1
        previousDay = currentDay
        continue
      }

      if calendar.isDate(currentDay, inSameDayAs: nextExpectedDay) {
        streak += 1
      } else {
        streak = 1
      }

      best = max(best, streak)
      previousDay = currentDay
    }

    return best
  }

  @MainActor
  static func totalWordsWritten(from entries: [Entry]) -> Int {
    entries.reduce(0) { total, entry in
      let userMessages = entry.conversation
        .filter { $0.role == .user }
        .map(\ .content)

      let normalizedObservation = normalizeText(entry.observation)
      let normalizedJoinedUserMessages = normalizeText(userMessages.joined(separator: " "))

      if !normalizedObservation.isEmpty,
        !normalizedJoinedUserMessages.isEmpty,
        normalizedObservation == normalizedJoinedUserMessages
      {
        return total + wordCount(in: entry.observation)
      }

      let openingText = entry.observation.isEmpty ? entry.canonicalOriginalText : entry.observation
      let openingWordCount = wordCount(in: openingText)
      let normalizedOpeningText = normalizeText(openingText)

      var hasSkippedMirroredOpening = false
      let userConversationWordCount = userMessages.reduce(0) { partialResult, message in
        let normalizedMessage = normalizeText(message)
        if !hasSkippedMirroredOpening,
          !normalizedOpeningText.isEmpty,
          normalizedMessage == normalizedOpeningText
        {
          hasSkippedMirroredOpening = true
          return partialResult
        }

        return partialResult + wordCount(in: message)
      }

      return total + openingWordCount + userConversationWordCount
    }
  }

  @MainActor
  static func mergedAnalytics(from records: [AnalyticsData]) -> ExportedAnalytics? {
    guard let first = records.first else { return nil }

    return records.dropFirst().reduce(
      ExportedAnalytics(
        totalSecondsSpent: first.totalSecondsSpent,
        totalAIResponsesGenerated: first.totalAIResponsesGenerated,
        totalUserResponses: first.totalUserResponses,
        totalConversations: first.totalConversations
      )
    ) { partial, record in
      ExportedAnalytics(
        totalSecondsSpent: max(partial.totalSecondsSpent, record.totalSecondsSpent),
        totalAIResponsesGenerated: max(partial.totalAIResponsesGenerated, record.totalAIResponsesGenerated),
        totalUserResponses: max(partial.totalUserResponses, record.totalUserResponses),
        totalConversations: max(partial.totalConversations, record.totalConversations)
      )
    }
  }

  private static func uniqueEntryDays(from entries: [Entry], calendar: Calendar) -> Set<Date> {
    Set(entries.map { calendar.startOfDay(for: $0.date) })
  }

  private static func wordCount(in text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
  }

  private static func normalizeText(_ text: String) -> String {
    text
      .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
      .joined(separator: " ")
      .lowercased()
  }
}

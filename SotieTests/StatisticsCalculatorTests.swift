import Foundation
import Testing

@testable import Sotie

@MainActor
struct StatisticsCalculatorTests {

  @Test func currentStreakTreatsYesterdayAsAStillActiveStreak() {
    let calendar = Calendar(identifier: .gregorian)
    let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    let today = calendar.startOfDay(for: referenceDate)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

    let streak = StatisticsCalculator.currentStreak(
      from: Set([yesterday, twoDaysAgo]),
      calendar: calendar,
      referenceDate: referenceDate
    )

    #expect(streak == 2)
  }

  @Test func currentStreakIgnoresDuplicateEntriesOnTheSameDay() {
    let calendar = Calendar(identifier: .gregorian)
    let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    let today = calendar.startOfDay(for: referenceDate)
    let laterToday = calendar.date(byAdding: .hour, value: 12, to: today)!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

    let entries = [
      Entry(observation: "Morning", date: today),
      Entry(observation: "Evening", date: laterToday),
      Entry(observation: "Yesterday", date: yesterday),
    ]

    let streak = StatisticsCalculator.currentStreak(
      from: entries,
      calendar: calendar,
      referenceDate: referenceDate
    )

    #expect(streak == 2)
  }

  @Test func bestStreakTracksTheLongestRunOfActiveDays() {
    let calendar = Calendar(identifier: .gregorian)
    let anchor = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
    let days = Set([
      anchor,
      calendar.date(byAdding: .day, value: -1, to: anchor)!,
      calendar.date(byAdding: .day, value: -4, to: anchor)!,
      calendar.date(byAdding: .day, value: -5, to: anchor)!,
      calendar.date(byAdding: .day, value: -6, to: anchor)!,
    ])

    let best = StatisticsCalculator.bestStreak(from: days, calendar: calendar)

    #expect(best == 3)
  }

  @Test func totalWordsWrittenDoesNotDoubleCountMirroredOpeningUserMessage() {
    let entry = Entry(observation: "I feel stuck today")
    entry.conversation = [
      DialogueMessage(role: .user, content: "I feel stuck today"),
      DialogueMessage(role: .assistant, content: "What makes it feel stuck?"),
      DialogueMessage(role: .user, content: "I keep repeating the same loop"),
    ]

    let total = StatisticsCalculator.totalWordsWritten(from: [entry])

    #expect(total == 10)
  }

  @Test func totalWordsWrittenIgnoresAssistantAndWhitespaceOnlyMessages() {
    let entry = Entry(observation: "  one\n two  ")
    entry.conversation = [
      DialogueMessage(role: .assistant, content: "assistant words should not count"),
      DialogueMessage(role: .user, content: "   \n  "),
      DialogueMessage(role: .user, content: "three   four"),
    ]

    let total = StatisticsCalculator.totalWordsWritten(from: [entry])

    #expect(total == 4)
  }

  @Test func totalWordsWrittenDoesNotDoubleCountSavedConversationObservationSnapshot() {
    let entry = Entry(observation: "I feel stuck I keep spiraling")
    entry.originalEntryText = "I feel stuck"
    entry.conversation = [
      DialogueMessage(role: .user, content: "I feel stuck"),
      DialogueMessage(role: .assistant, content: "What happens next?"),
      DialogueMessage(role: .user, content: "I keep spiraling"),
    ]

    let total = StatisticsCalculator.totalWordsWritten(from: [entry])

    #expect(total == 6)
  }
}

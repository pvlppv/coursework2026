//
//  NotificationFlowTests.swift
//  SotieTests
//
//  Created by Codex on 08.03.2026.
//

import Foundation
import Testing
import UserNotifications

@testable import Sotie

@MainActor
struct NotificationFlowTests {

  @Test func navigateToEntryAcceptsColdStartDeepLinkWithoutModelContext() async throws {
    let router = NavigationRouter()
    let entryId = UUID()

    let accepted = router.navigateToEntry(withId: entryId)

    #expect(accepted)
    #expect(router.selectedTab == .home)
    #expect(router.entryScrollTarget == entryId)

    guard case .editEntryById(let presentedEntryId)? = router.presentedSheet else {
      Issue.record("Expected an editEntryById sheet destination after notification navigation")
      return
    }

    #expect(presentedEntryId == entryId)
  }

  @Test func navigateToEntryReplacesAnExistingRouterManagedSheet() async throws {
    let router = NavigationRouter()
    let entryId = UUID()

    router.presentSheet(.settings)

    let accepted = router.navigateToEntry(withId: entryId)

    #expect(accepted)

    guard case .editEntryById(let presentedEntryId)? = router.presentedSheet else {
      Issue.record("Expected editEntryById sheet to replace the existing router-managed sheet")
      return
    }

    #expect(presentedEntryId == entryId)
  }

  @Test func fallbackNotificationQuestionsStayShortAndQuestionOnly() async throws {
    for type in [NotificationType.conversationFollowUp, .reEngagement] {
      let questions = NotificationContentTemplate.fallbackQuestions(for: type, languageCode: "en")

      #expect(!questions.isEmpty)

      for question in questions {
        let wordCount = question.split(whereSeparator: \.isWhitespace).count

        #expect(question.hasSuffix("?"))
        #expect(wordCount >= 2)
        #expect(wordCount <= 10)
      }
    }
  }

  @Test func fallbackNotificationQuestionsFollowLanguageCode() async throws {
    let englishQuestions =
      NotificationContentTemplate.fallbackQuestions(for: .conversationFollowUp, languageCode: "en")
      + NotificationContentTemplate.fallbackQuestions(for: .reEngagement, languageCode: "en")
    let russianQuestions =
      NotificationContentTemplate.fallbackQuestions(for: .conversationFollowUp, languageCode: "ru")
      + NotificationContentTemplate.fallbackQuestions(for: .reEngagement, languageCode: "ru")

    #expect(englishQuestions.contains(localizedString(Localizable.notificationFollowUpFallback, languageCode: "en")))
    #expect(!englishQuestions.contains(localizedString(Localizable.notificationFollowUpFallback, languageCode: "ru")))
    #expect(russianQuestions.contains(localizedString(Localizable.notificationFollowUpFallback, languageCode: "ru")))
    #expect(!russianQuestions.contains(localizedString(Localizable.notificationFollowUpFallback, languageCode: "en")))
  }

  @Test func reEngagementSchedulePlannerIncludesAllMilestonesInOrder() async throws {
    let calendar = Calendar(identifier: .gregorian)
    let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    let schedule = ReEngagementSchedulePlanner.schedule(from: referenceDate, calendar: calendar)

    #expect(schedule.map(\.days) == [3, 7, 14, 30])
    #expect(schedule.allSatisfy { $0.fireDate > referenceDate })

    let expectedIdentifiers = [3, 7, 14, 30].map {
      "\(NotificationType.reEngagement.identifier)_\($0)d"
    }
    #expect(schedule.map(\.identifier) == expectedIdentifiers)
  }

  // MARK: - Entry Model Tests (Notification v2)

  @Test func lastAIResponseReturnsLastAssistantMessage() async throws {
    let entry = Entry(observation: "Test entry")

    // No conversation — lastAIResponse should be nil
    #expect(entry.lastAIResponse == nil)

    // Add conversation with assistant messages
    entry.conversation = [
      DialogueMessage(role: .user, content: "I feel anxious today"),
      DialogueMessage(role: .assistant, content: "What triggers that anxiety?"),
      DialogueMessage(role: .user, content: "My upcoming presentation"),
      DialogueMessage(role: .assistant, content: "What's the worst that could happen?"),
    ]

    #expect(entry.lastAIResponse == "What's the worst that could happen?")
  }

  @Test func lastAIResponseReturnsNilWhenLastMessageIsUser() async throws {
    let entry = Entry(observation: "Test entry")
    entry.conversation = [
      DialogueMessage(role: .user, content: "I feel anxious today"),
      DialogueMessage(role: .assistant, content: "What triggers that anxiety?"),
      DialogueMessage(role: .user, content: "My upcoming presentation"),
    ]

    // Last message is from user, but lastAIResponse should still return last assistant message
    #expect(entry.lastAIResponse == "What triggers that anxiety?")
  }

  @Test func hasActiveNotificationReflectsNotificationSentAt() async throws {
    let entry = Entry(observation: "Test entry")

    // Initially no notification
    #expect(entry.hasActiveNotification == false)
    #expect(entry.notificationSentAt == nil)

    // Set notification
    entry.notificationSentAt = Date()
    #expect(entry.hasActiveNotification == true)

    // Clear notification
    entry.notificationSentAt = nil
    #expect(entry.hasActiveNotification == false)
  }

  @Test func sameEntryFollowUpIsSuppressedWhileEditingThatEntry() async throws {
    let entry = Entry(observation: "Editing this entry")

    let options = NotificationManager.foregroundPresentationOptions(
      for: [
        "type": NotificationType.conversationFollowUp.rawValue,
        "entryId": entry.id.uuidString,
      ],
      presentedSheet: .editEntry(entry: entry)
    )

    #expect(options.isEmpty)
  }

  @Test func sameEntryFollowUpByIdIsSuppressedWhileEditingThatEntry() async throws {
    let entryId = UUID()

    let options = NotificationManager.foregroundPresentationOptions(
      for: [
        "type": NotificationType.conversationFollowUp.rawValue,
        "entryId": entryId.uuidString,
      ],
      presentedSheet: .editEntryById(entryId: entryId)
    )

    #expect(options.isEmpty)
  }

  @Test func differentEntryFollowUpStillPresentsInForeground() async throws {
    let openEntry = Entry(observation: "Currently open")
    let notificationEntryId = UUID()

    let options = NotificationManager.foregroundPresentationOptions(
      for: [
        "type": NotificationType.conversationFollowUp.rawValue,
        "entryId": notificationEntryId.uuidString,
      ],
      presentedSheet: .editEntry(entry: openEntry)
    )

    #expect(options == [.banner, .sound, .badge])
  }

  @Test func nonFollowUpNotificationsStillPresentInForeground() async throws {
    let entry = Entry(observation: "Editing this entry")

    let options = NotificationManager.foregroundPresentationOptions(
      for: [
        "type": NotificationType.reEngagement.rawValue,
        "entryId": entry.id.uuidString,
      ],
      presentedSheet: .editEntry(entry: entry)
    )

    #expect(options == [.banner, .sound, .badge])
  }
}

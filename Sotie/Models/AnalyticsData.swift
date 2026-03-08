import Foundation
import SwiftData

@Model
final class AnalyticsData {
  var id: UUID = UUID()

  // Time tracking (in seconds for precision)
  var totalSecondsSpent: Double = 0

  // AI conversation metrics
  var totalAIResponsesGenerated: Int = 0
  var totalUserResponses: Int = 0
  var totalConversations: Int = 0

  // Last updated timestamp
  var lastUpdated: Date = Date()

  init() {
    self.id = UUID()
    self.totalSecondsSpent = 0
    self.totalAIResponsesGenerated = 0
    self.totalUserResponses = 0
    self.totalConversations = 0
    self.lastUpdated = Date()
  }

  // MARK: - Computed Properties

  var totalMinutesSpent: Int {
    Int(totalSecondsSpent / 60)
  }

  var averageConversationDepth: Double {
    guard totalConversations > 0 else { return 0 }
    return Double(totalAIResponsesGenerated) / Double(totalConversations)
  }

  var formattedTimeSpent: String {
    let hours = Int(totalSecondsSpent) / 3600
    let minutes = (Int(totalSecondsSpent) % 3600) / 60

    if hours > 0 {
      return
        "\(hours)\(appLocalizedString(Localizable.analyticsHours)) \(minutes)\(appLocalizedString(Localizable.analyticsMinutes))"
    } else {
      return "\(minutes)\(appLocalizedString(Localizable.analyticsMinutes))"
    }
  }

  // MARK: - Update Methods

  func addTimeSpent(seconds: Double) {
    totalSecondsSpent += seconds
    lastUpdated = Date()
  }

  func recordAIResponse() {
    totalAIResponsesGenerated += 1
    lastUpdated = Date()
  }

  func recordUserResponse() {
    totalUserResponses += 1
    lastUpdated = Date()
  }

  func recordConversation() {
    totalConversations += 1
    lastUpdated = Date()
  }
}

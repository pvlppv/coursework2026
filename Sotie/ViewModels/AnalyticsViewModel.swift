import Combine
import Foundation
import os
import SwiftData
import SwiftUI

@MainActor
class AnalyticsViewModel: ObservableObject {
  @Published var timeSpent: String = "0m"
  @Published var aiResponsesCount: Int = 0
  @Published var userResponsesCount: Int = 0
  @Published var avgConversationDepth: String = "0.0"
  @Published var hasData: Bool = false

  func loadAnalytics() {
    // Get data from analytics tracker
    let tracker = AnalyticsTracker.shared

    timeSpent = tracker.totalTimeSpent
    aiResponsesCount = tracker.totalAIResponses
    userResponsesCount = tracker.totalUserResponses

    let depth = tracker.averageConversationDepth
    if depth == depth.rounded() {
      avgConversationDepth = String(format: "%.0f", depth)
    } else {
      avgConversationDepth = String(format: "%.1f", depth)
    }

    hasData = tracker.hasAnyData

    AppLogger.data.debug("Loaded analytics: Time=\(self.timeSpent), AI=\(self.aiResponsesCount), User=\(self.userResponsesCount), Depth=\(self.avgConversationDepth)")
  }

  func refresh() {
    loadAnalytics()
  }

  // MARK: - Entry-derived Metrics

  /// Current streak of consecutive days with entries
  static func reflectionStreak(from entries: [Entry]) -> Int {
    StatisticsCalculator.currentStreak(from: entries)
  }

  /// Total words written across all entries
  static func totalWordsWritten(from entries: [Entry]) -> Int {
    StatisticsCalculator.totalWordsWritten(from: entries)
  }


  /// Format word count for display (1k, 1.2k, 15k, etc.)
  static func formattedWordCount(_ count: Int) -> String {
    if count >= 1000 {
      let k = Double(count) / 1000.0
      if k == k.rounded() {
        return String(format: "%.0fk", k)
      }
      return String(format: "%.1fk", k)
    }
    return "\(count)"
  }
}

import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
class DashboardViewModel: ObservableObject {
  // FAB state
  @Published var fabScale: CGFloat = 1.0

  private var modelContext: ModelContext?
  private var isConfigured = false

  // MARK: - Initialization
  func initialize(with modelContext: ModelContext) {
    // Prevent duplicate initialization
    guard !isConfigured else { return }

    self.modelContext = modelContext
    isConfigured = true
  }

  // MARK: - Summary Statistics
  func calculateSummaryStats(from entries: [Entry]) -> (
    entriesCount: Int, totalEntries: Int, currentStreak: Int
  ) {
    let entriesCount = entries.count
    let totalEntries = entries.count

    let streak = calculateCurrentStreak(from: entries)
    updateCachedStreak(streak)

    return (entriesCount, totalEntries, streak)
  }

  // Cache for streak calculation
  @Published private var cachedStreak: Int?
  private var cachedStreakDate: Date = Date.distantPast

  private func updateCachedStreak(_ streak: Int) {
    cachedStreak = streak
    cachedStreakDate = Date()
    objectWillChange.send()
  }

  private func calculateCurrentStreak(from entries: [Entry]) -> Int {
    StatisticsCalculator.currentStreak(from: entries)
  }

  // MARK: - Entry Operations
  func createEntry() {
    // This will trigger navigation to entry creation
    // Handled by NavigationRouter
  }

  // MARK: - Progress Update (simplified)
  func updateProgress() {
    // No insight progress tracking needed
  }
}

// MARK: - Helper Extensions
extension DashboardViewModel {
  var hasAnyEntries: Bool {
    // This will be provided by the view via entries query
    true
  }
}

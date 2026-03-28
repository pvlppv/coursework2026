import Foundation

struct DataAggregator {

  /// Aggregates entries by day based on the specified display mode
  func aggregateEntriesByDay(_ entries: [Entry], mode: HeatmapDisplayMode) -> [Date: (
    value: Double, count: Int
  )] {
    let calendar = LanguageManager.shared.calendar
    var dailyData: [Date: (value: Double, count: Int)] = [:]

    // Group entries by day
    let groupedEntries = Dictionary(grouping: entries) { entry in
      calendar.startOfDay(for: entry.date)
    }

    for (date, dayEntries) in groupedEntries {
      let count = dayEntries.count
      let value: Double

      switch mode {
      case .quantity:
        value = Double(count)
      case .valueSum:
        value = dayEntries.compactMap { $0.extractedValue }.reduce(0, +)
      }

      dailyData[date] = (value: value, count: count)
    }

    return dailyData
  }

  /// Calculates streaks from daily data
  func calculateStreaks(from dailyData: [Date: (value: Double, count: Int)]) -> (
    current: Int, best: Int
  ) {
    let calendar = LanguageManager.shared.calendar
    let activeDays = Set(
      dailyData.compactMap { date, value in
        value.count > 0 ? calendar.startOfDay(for: date) : nil
      }
    )
    let currentStreak = StatisticsCalculator.currentStreak(from: activeDays, calendar: calendar)
    let bestStreak = StatisticsCalculator.bestStreak(from: activeDays, calendar: calendar)

    return (current: currentStreak, best: bestStreak)
  }

  /// Calculates basic statistics from daily data
  func calculateStatistics(
    from dailyData: [Date: (value: Double, count: Int)], mode: HeatmapDisplayMode
  ) -> DayStatistics {
    let values = dailyData.values.map { $0.value }
    let counts = dailyData.values.map { $0.count }

    guard !values.isEmpty else {
      return DayStatistics(
        totalEntries: 0,
        totalValue: 0,
        averageValue: 0,
        averageEntriesPerDay: 0,
        activeDays: 0
      )
    }

    let totalEntries = counts.reduce(0, +)
    let totalValue = values.reduce(0, +)
    let activeDays = dailyData.count

    let averageValue = totalValue / Double(activeDays)
    let averageEntriesPerDay = Double(totalEntries) / Double(activeDays)

    return DayStatistics(
      totalEntries: totalEntries,
      totalValue: totalValue,
      averageValue: averageValue,
      averageEntriesPerDay: averageEntriesPerDay,
      activeDays: activeDays
    )
  }
}

// MARK: - Supporting Types

struct DayStatistics {
  let totalEntries: Int
  let totalValue: Double
  let averageValue: Double
  let averageEntriesPerDay: Double
  let activeDays: Int
}

import Foundation

/// Centralized date formatting utility that respects user's locale and calendar preferences
struct DateFormatter {

  // MARK: - Private Properties

  private static var calendar: Calendar {
    LanguageManager.shared.calendar
  }

  private static var locale: Locale {
    LanguageManager.shared.locale
  }

  private static var timeZone: TimeZone {
    LanguageManager.shared.timeZone
  }

  // MARK: - Public Methods

  /// Formats a date for display in entry cards and lists
  /// Uses proper year comparison with Calendar.isDate(_:equalTo:toGranularity:)
  static func formatDateTimeForCard(_ date: Date) -> String {
    let now = Date()

    if calendar.isDate(date, equalTo: now, toGranularity: .year) {
      // Same year - show without year
      return date.formatted(
        .dateTime
          .day()
          .month()
          .hour(.defaultDigits(amPM: .omitted))
          .minute()
          .locale(locale)
      )
    } else {
      // Different year - show with year
      return date.formatted(
        .dateTime
          .day()
          .month()
          .year()
          .hour(.defaultDigits(amPM: .omitted))
          .minute()
          .locale(locale)
      )
    }
  }

  /// Formats a date for entry creation/editing
  /// Uses proper year comparison with Calendar.isDate(_:equalTo:toGranularity:)
  static func formatDateTimeForEntry(_ date: Date) -> String {
    let now = Date()

    if calendar.isDate(date, equalTo: now, toGranularity: .year) {
      // Same year - show without year
      return date.formatted(
        .dateTime
          .day()
          .month()
          .hour(.defaultDigits(amPM: .omitted))
          .minute()
          .locale(locale)
      )
    } else {
      // Different year - show with year
      return date.formatted(
        .dateTime
          .day()
          .month()
          .year()
          .hour(.defaultDigits(amPM: .omitted))
          .minute()
          .locale(locale)
      )
    }
  }

  /// Formats a date range for export descriptions
  static func formatDateRange(_ startDate: Date, _ endDate: Date) -> String {
    let formatter = Foundation.DateFormatter()
    formatter.locale = locale
    formatter.dateStyle = .short
    return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
  }

  /// Formats a date for short display (day and month only)
  static func formatShortDate(_ date: Date) -> String {
    return date.formatted(
      .dateTime
        .day()
        .month()
        .locale(locale)
    )
  }

  /// Formats a date for long display (full date with year)
  static func formatLongDate(_ date: Date) -> String {
    return date.formatted(
      .dateTime
        .day()
        .month()
        .year()
        .locale(locale)
    )
  }

  /// Formats time only
  static func formatTime(_ date: Date) -> String {
    return date.formatted(
      .dateTime
        .hour(.defaultDigits(amPM: .omitted))
        .minute()
        .locale(locale)
    )
  }

  /// Checks if two dates are in the same day
  static func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
    return calendar.isDate(date1, inSameDayAs: date2)
  }

  /// Checks if two dates are in the same year
  static func isSameYear(_ date1: Date, _ date2: Date) -> Bool {
    return calendar.isDate(date1, equalTo: date2, toGranularity: .year)
  }

  /// Gets the start of day for a given date
  static func startOfDay(for date: Date) -> Date {
    return calendar.startOfDay(for: date)
  }

  /// Gets the end of day for a given date
  static func endOfDay(for date: Date) -> Date {
    let startOfDay = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .day, value: 1, to: startOfDay)?.addingTimeInterval(-1) ?? date
  }

  /// Formats a date with timezone consideration
  static func formatDateTimeWithTimezone(_ date: Date) -> String {
    let now = Date()

    if calendar.isDate(date, equalTo: now, toGranularity: .year) {
      return date.formatted(
        .dateTime
          .day()
          .month()
          .hour(.defaultDigits(amPM: .omitted))
          .minute()
          .locale(locale)
      )
    } else {
      return date.formatted(
        .dateTime
          .day()
          .month()
          .year()
          .hour(.defaultDigits(amPM: .omitted))
          .minute()
          .locale(locale)
      )
    }
  }

  /// Formats a date for relative display (Today, Yesterday, etc.)
  static func formatRelativeDate(_ date: Date) -> String {
    let now = Date()

    if calendar.isDate(date, inSameDayAs: now) {
      return appLocalizedString(Localizable.today)
    } else if calendar.isDate(
      date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now)
    {
      return appLocalizedString(Localizable.yesterday)
    } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
      return date.formatted(.dateTime.weekday(.wide).locale(locale))
    } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
      return date.formatted(.dateTime.month(.wide).day().locale(locale))
    } else {
      return date.formatted(.dateTime.month(.wide).day().year().locale(locale))
    }
  }

  /// Gets the start of week for a given date
  static func startOfWeek(for date: Date) -> Date {
    return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
  }

  /// Gets the end of week for a given date
  static func endOfWeek(for date: Date) -> Date {
    return calendar.dateInterval(of: .weekOfYear, for: date)?.end ?? date
  }

  /// Gets the start of month for a given date
  static func startOfMonth(for date: Date) -> Date {
    return calendar.dateInterval(of: .month, for: date)?.start ?? date
  }

  /// Gets the end of month for a given date
  static func endOfMonth(for date: Date) -> Date {
    return calendar.dateInterval(of: .month, for: date)?.end ?? date
  }

  /// Formats a date for CSV export (short date format)
  static func formatDateForCSV(_ date: Date) -> String {
    let formatter = Foundation.DateFormatter()
    formatter.locale = locale
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }

  /// Formats a date for CSV export with time
  static func formatDateTimeForCSV(_ date: Date) -> String {
    let formatter = Foundation.DateFormatter()
    formatter.locale = locale
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  /// Formats a date for filename generation (ISO format)
  static func formatDateForFilename(_ date: Date) -> String {
    let formatter = Foundation.DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  /// Formats a month name (e.g., "January", "February")
  static func formatMonthName(_ date: Date) -> String {
    let formatter = Foundation.DateFormatter()
    formatter.locale = locale
    formatter.dateFormat = "LLLL"
    return formatter.string(from: date)
  }

  /// Formats a month name with year (e.g., "January 2024", "February 2023")
  static func formatMonthNameWithYear(_ date: Date) -> String {
    let formatter = Foundation.DateFormatter()
    formatter.locale = locale
    formatter.dateFormat = "LLLL yyyy"
    return formatter.string(from: date)
  }

  /// Formats a date for debugging/logging
  static func formatDateForDebug(_ date: Date) -> String {
    let formatter = Foundation.DateFormatter()
    formatter.locale = locale
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}

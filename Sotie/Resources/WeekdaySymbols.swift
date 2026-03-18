import Foundation

/// Locale-aware weekday symbol helper for compact calendar UIs.
///
/// We need very-short symbols (one or two glyphs) that:
///   1. Render reliably for every supported locale.
///   2. Look readable in CJK + Cyrillic (single Latin letters cluster
///      meaninglessly in those scripts).
///   3. Don't accidentally render empty strings — which is the default
///      behavior of `DateFormatter.veryShortStandaloneWeekdaySymbols`
///      for some locale/region combinations on iOS 18+.
///
/// Strategy: prefer `shortStandaloneWeekdaySymbols` (e.g. "Mon", "Пн", "月")
/// and trim down to the leading display character(s). For Latin scripts we
/// take the first character; for non-Latin scripts we keep up to two so
/// "Пн", "Сб", "월" remain legible.
enum WeekdaySymbols {

  /// Returns the very-short weekday label for the given date in the active
  /// calendar/locale. Examples:
  ///   • EN: "M", "T", "W", "T", "F", "S", "S"
  ///   • RU: "Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"
  ///   • JA: "月", "火", "水", "木", "金", "土", "日"
  ///   • KO: "월", "화", "수", "목", "금", "토", "일"
  static func veryShort(for date: Date, calendar: Calendar, locale: Locale) -> String {
    let weekday = calendar.component(.weekday, from: date)
    return symbol(forWeekdayIndex: weekday - 1, calendar: calendar, locale: locale)
  }

  /// Header letters in display order (i.e. starting from `calendar.firstWeekday`),
  /// suitable for a 7-column calendar grid header.
  static func headerSymbols(calendar: Calendar, locale: Locale) -> [String] {
    let first = calendar.firstWeekday - 1
    return (0..<7).map { offset in
      symbol(forWeekdayIndex: (first + offset) % 7, calendar: calendar, locale: locale)
    }
  }

  // MARK: - Private

  /// `weekdayIndex` is 0-based with Sunday = 0 (matches Foundation's symbol
  /// arrays which are always Sunday-anchored regardless of `firstWeekday`).
  private static func symbol(
    forWeekdayIndex weekdayIndex: Int,
    calendar: Calendar,
    locale: Locale
  ) -> String {
    let formatter = Foundation.DateFormatter()
    formatter.locale = locale
    formatter.calendar = calendar

    // Try standalone short first ("Mon", "Пн", "月") — this is the most
    // reliably populated symbol set across locales.
    let shortStandalone = formatter.shortStandaloneWeekdaySymbols ?? []
    if weekdayIndex < shortStandalone.count {
      let raw = shortStandalone[weekdayIndex]
      return condense(raw, locale: locale)
    }

    // Fallback to non-standalone short.
    let short = formatter.shortWeekdaySymbols ?? []
    if weekdayIndex < short.count {
      return condense(short[weekdayIndex], locale: locale)
    }

    return ""
  }

  /// Trim a short weekday string down to its display glyphs. For Latin
  /// scripts we keep the first character; for non-Latin (Cyrillic, CJK,
  /// Hangul, Thai, Greek, etc.) we keep up to two characters because a
  /// single character is often ambiguous (e.g. RU has Tuesday "В" and
  /// Friday "П" colliding with weekend "В" and Monday "П").
  private static func condense(_ symbol: String, locale: Locale) -> String {
    let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    if isLatinScriptDominant(in: trimmed) {
      return String(trimmed.prefix(1)).uppercased(with: locale)
    }

    // Non-Latin: keep up to 2 characters (the form Foundation already
    // returns for short symbols in CJK/Cyrillic locales).
    return String(trimmed.prefix(2))
  }

  private static func isLatinScriptDominant(in string: String) -> Bool {
    guard let first = string.unicodeScalars.first else { return true }
    return first.value < 0x0370 // Below Greek/Cyrillic block start
  }
}

import SwiftData
import SwiftUI

/// Reflections sheet — presented when the user taps the "This week"
/// banner on home. The single source of truth for everything related
/// to the user's reflection rhythm.
///
/// Layout (top to bottom):
///   1. Hero card — REFLECTIONS pill + big total + Sotie nudge inside.
///      The nudge is the same state-aware line we used to surface as a
///      separate "AI message" tile, but now it lives under the count
///      so the screen opens with one confident statement.
///   2. Streak tiles — current + longest, monochrome flame icon.
///   3. Volume tiles — time reflecting + words written.
///   4. Monthly calendars — only months that contain at least one
///      reflection day. Bounded list, ends with the very first month
///      the user reflected. No infinite-padding back into empty
///      history (which made the old "Reflecting since" footer
///      unreachable).
///   5. "Reflecting since [Month YYYY]" — quiet centered footnote at
///      the bottom of the scroll.
struct ReflectionsCalendarSheet: View {

  // MARK: - Data

  @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
  @EnvironmentObject private var languageManager: LanguageManager
  @StateObject private var analyticsViewModel = AnalyticsViewModel()

  // MARK: - Derived

  private var calendar: Calendar { languageManager.calendar }

  private var reflectedDays: Set<Date> {
    ReflectionSignals.reflectedDays(from: entries, calendar: calendar)
  }

  private var currentStreak: Int {
    StatisticsCalculator.currentStreak(from: reflectedDays, calendar: calendar)
  }

  private var bestStreak: Int {
    StatisticsCalculator.bestStreak(from: reflectedDays, calendar: calendar)
  }

  private var totalWords: Int {
    AnalyticsViewModel.totalWordsWritten(from: entries)
  }

  /// Months (oldest-first → newest-last reversed for display) that have
  /// at least one reflection day. The old version walked back in fixed
  /// 6-month chunks regardless of activity; now every card on screen
  /// earns its place by containing real dots.
  private var monthsToShow: [Date] {
    guard !reflectedDays.isEmpty else { return [] }

    var months: Set<Date> = []
    for day in reflectedDays {
      if let monthStart = calendar.dateInterval(of: .month, for: day)?.start {
        months.insert(monthStart)
      }
    }
    return months.sorted(by: >)  // newest first; current month at top
  }

  /// Earliest reflection date — anchors the "Reflecting since" footer.
  private var earliestReflectionDate: Date? {
    entries.last?.date
  }

  // MARK: - Body

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: Spacing.medium) {
          heroCard

          metricsGrid

          ForEach(monthsToShow, id: \.self) { monthStart in
            MonthCalendarCard(
              monthStart: monthStart,
              reflectedDays: reflectedDays
            )
          }

          if let earliestReflectionDate {
            sinceFooter(date: earliestReflectionDate)
              .padding(.top, Spacing.small)
          }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.medium)
        .padding(.bottom, Spacing.xxLarge)
      }
      .scrollIndicators(.hidden)
      .themeBackground(.primary)
      .navigationTitle(LocalizedStringKey(Localizable.reflectionsTitle))
      .navigationBarTitleDisplayMode(.inline)
    }
    .onAppear {
      analyticsViewModel.loadAnalytics()
    }
  }

  // MARK: - Hero card

  /// Streak owns the screen. Rendered as one phrase: flame + "1 day"
  /// in a single Text concatenation. Same color, same weight, same
  /// size — no per-glyph styling. Sotie nudge sits below with the
  /// canonical AI message styling (sparkle + body text, both
  /// secondary).
  private var heroCard: some View {
    let nudge = ReflectionNudge.resolve(
      currentStreak: currentStreak,
      bestStreak: bestStreak
    )
    return VStack(alignment: .leading, spacing: Spacing.medium) {
      Text("\(Image(systemName: "flame.fill")) \(currentStreak) \(dayUnit(for: currentStreak))")
        .font(.system(size: 48, weight: .bold).monospacedDigit())
        .foregroundColor(Color.theme.textPrimary)

      // Nudge — exact AI message styling, baseline-aligned so the
      // sparkle sits on the first line of the body text instead of
      // floating above it.
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
        Image(systemName: "sparkles")
          .font(.system(size: 18, weight: .medium))
          .themeText(.secondary)

        Text(LocalizedStringKey(nudge.localizationKey))
          .typography(.body)
          .themeText(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.large)
    .background(
      RoundedRectangle(cornerRadius: Spacing.cornerRadiusLarge, style: .continuous)
        .fill(Color.theme.backgroundSecondary)
        .themeShadow(.medium)
    )
  }

  // MARK: - Metrics grid (2×2)

  /// Four supporting metrics in a clean 2×2 grid:
  ///   • Best streak  |  Time reflecting
  ///   • Reflections  |  Words written
  ///
  /// Two-per-row gives every value enough horizontal room to render
  /// large numbers without overflow risk. Same chrome on every tile;
  /// values are pre-formatted strings so the unit reads as part of
  /// the number ("1d" / "8m") in one consistent type treatment.
  private var metricsGrid: some View {
    VStack(spacing: Spacing.medium) {
      HStack(spacing: Spacing.medium) {
        metricTile(
          labelKey: Localizable.reflectionsLongestStreak,
          value: "\(bestStreak)\(appLocalizedString(Localizable.analyticsDayShort))"
        )
        metricTile(
          labelKey: Localizable.analyticsTimeReflecting,
          value: analyticsViewModel.timeSpent
        )
      }
      HStack(spacing: Spacing.medium) {
        metricTile(
          labelKey: Localizable.analyticsReflections,
          value: "\(entries.count)"
        )
        metricTile(
          labelKey: Localizable.analyticsWordsWritten,
          value: AnalyticsViewModel.formattedWordCount(totalWords)
        )
      }
    }
  }

  private func metricTile(
    labelKey: String,
    value: String
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xSmall) {
      microCaption(LocalizedStringKey(labelKey))

      Text(value)
        .font(.system(size: 26, weight: .semibold).monospacedDigit())
        .foregroundColor(Color.theme.textPrimary)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.medium)
    .background(
      RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium, style: .continuous)
        .fill(Color.theme.backgroundSecondary)
    )
  }

  // MARK: - Footer

  /// "Reflecting since [Month YYYY]" — quiet centered footnote at the
  /// very bottom of the scroll. Hidden when the user only reflected
  /// today (saying "since May 2026" on day-zero reads odd).
  @ViewBuilder
  private func sinceFooter(date: Date) -> some View {
    if !calendar.isDateInToday(date) {
      Text(
        appLocalizedString(
          Localizable.analyticsReflectingSince,
          arguments: formattedSinceMonth(date)
        )
      )
      .font(.footnote)
      .foregroundColor(Color.theme.textTertiary)
      .frame(maxWidth: .infinity)
    }
  }

  // MARK: - Microcaption

  private func microCaption(_ text: LocalizedStringKey) -> some View {
    Text(text)
      .font(.system(size: 11, weight: .semibold))
      .foregroundColor(Color.theme.textSecondary)
      .textCase(.uppercase)
      .tracking(0.8)
      .lineLimit(2)
      .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Helpers

  /// Locale-aware "day"/"days" using Russian 3-form pluralization where
  /// applicable. Same call shape used in the previous version.
  private func dayUnit(for count: Int) -> String {
    languageManager.pluralize(
      count,
      appLocalizedString(Localizable.reflectionsDayUnitOne),
      appLocalizedString(Localizable.reflectionsDayUnitFew),
      appLocalizedString(Localizable.reflectionsDayUnitMany)
    )
  }

  /// Locale-aware "May 2026" / "Май 2026" / "5月 2026". Uses the
  /// natural title case the locale produces — lowercasing breaks
  /// languages that capitalize months.
  private func formattedSinceMonth(_ date: Date) -> String {
    let formatter = Foundation.DateFormatter()
    formatter.locale = languageManager.locale
    formatter.calendar = calendar
    formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
    return formatter.string(from: date)
  }
}

// MARK: - MonthCalendarCard

/// A single month's calendar, rendered as a 7-column grid of circles.
private struct MonthCalendarCard: View {

  let monthStart: Date
  let reflectedDays: Set<Date>

  @EnvironmentObject private var languageManager: LanguageManager

  private let dotSize: CGFloat = 32
  private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

  private var calendar: Calendar { languageManager.calendar }

  var body: some View {
    VStack(spacing: Spacing.medium) {
      monthHeader
      weekdayLabels
      daysGrid
    }
    .padding(Spacing.medium)
    .background(
      RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium, style: .continuous)
        .fill(Color.theme.backgroundSecondary)
    )
  }

  /// Month header. We always include the year so users scrolling years back
  /// (e.g. after import) keep their bearings instead of seeing six identical
  /// "May" headers in a row.
  private var monthHeader: some View {
    let raw = DateFormatter.formatMonthNameWithYear(monthStart)
    let title = raw.prefix(1).uppercased() + raw.dropFirst()
    return Text(title)
      .font(.headline)
      .foregroundColor(Color.theme.textPrimary)
      .frame(maxWidth: .infinity)
  }

  private var weekdayLabels: some View {
    LazyVGrid(columns: columns, spacing: 4) {
      ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { _, letter in
        Text(letter)
          .font(.caption.weight(.medium))
          .foregroundColor(Color.theme.textTertiary)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var daysGrid: some View {
    LazyVGrid(columns: columns, spacing: 6) {
      ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
        dayCell(cell)
      }
    }
  }

  @ViewBuilder
  private func dayCell(_ cell: DayCell) -> some View {
    if let day = cell.date {
      let isReflected = reflectedDays.contains(day)
      let isToday = calendar.isDateInToday(day)
      let isFuture = day > calendar.startOfDay(for: Date())

      ZStack {
        if isReflected {
          Circle()
            .fill(Color.theme.accentPrimary)
        } else if isToday {
          Circle()
            .stroke(Color.theme.accentPrimary, lineWidth: 1.5)
        }

        Text("\(calendar.component(.day, from: day))")
          .font(.system(size: 13, weight: isReflected ? .semibold : .regular))
          .foregroundColor(
            isReflected
              ? Color.theme.buttonText
              : (isFuture ? Color.theme.textTertiary.opacity(0.5) : Color.theme.textSecondary)
          )
      }
      .frame(width: dotSize, height: dotSize)
      .frame(maxWidth: .infinity)
    } else {
      Color.clear
        .frame(width: dotSize, height: dotSize)
        .frame(maxWidth: .infinity)
    }
  }

  // MARK: - Layout helpers

  private struct DayCell {
    let date: Date?  // nil = leading padding cell
  }

  /// Single-letter weekday header row, ordered by the active calendar's
  /// `firstWeekday`. Uses our own `WeekdaySymbols` helper instead of
  /// `DateFormatter.veryShortStandaloneWeekdaySymbols`, which on iOS 18+
  /// has been observed to return empty strings for some locale/region
  /// combinations (Thursday + Sunday going blank in en_RU was the
  /// trigger).
  private var weekdayHeaders: [String] {
    WeekdaySymbols.headerSymbols(
      calendar: calendar,
      locale: languageManager.locale
    )
  }

  /// Cells filling the calendar grid, with leading nil padding so the first
  /// real day lands under the correct weekday column.
  private var monthCells: [DayCell] {
    guard
      let monthInterval = calendar.dateInterval(of: .month, for: monthStart)
    else {
      return []
    }

    let firstDay = calendar.startOfDay(for: monthInterval.start)
    let firstWeekday = calendar.component(.weekday, from: firstDay)
    let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

    let dayCount = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 30

    var cells: [DayCell] = Array(repeating: DayCell(date: nil), count: leading)
    for offset in 0..<dayCount {
      if let date = calendar.date(byAdding: .day, value: offset, to: firstDay) {
        cells.append(DayCell(date: calendar.startOfDay(for: date)))
      }
    }
    return cells
  }
}

#Preview {
  ReflectionsCalendarSheet()
    .environmentObject(LanguageManager.shared)
    .modelContainer(for: Entry.self, inMemory: true)
}

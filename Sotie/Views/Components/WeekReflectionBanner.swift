import SwiftUI

/// Compact "this week" banner showing seven days as filled / empty circles.
/// Tapping the banner opens the full reflections calendar sheet.
///
/// This view is designed to live inside a `List` with `.listStyle(.insetGrouped)`
/// as its own `Section`. The host list provides the rounded card chrome
/// (corners, shadow, horizontal inset) so the banner reads as part of the
/// same visual family as the entry cards below it. We deliberately do NOT
/// draw our own background, corner radius, or shadow here — adding any of
/// those would either fight the system rendering or produce double-shadows.
struct WeekReflectionBanner: View {

  // MARK: - Configuration

  let reflectedDays: Set<Date>
  let onTap: () -> Void

  // MARK: - Sizing

  /// 36pt: a step down from 40 (which dominated the row) and a step up
  /// from 32 (which left too much air between dots). At 36pt the dots
  /// read as the primary content without overpowering the card height.
  private let dotSize: CGFloat = 36
  private let todayMarkerSize: CGFloat = 4

  // MARK: - Environment

  @EnvironmentObject private var languageManager: LanguageManager

  // MARK: - Body

  var body: some View {
    // Why not a `Button`? In `.insetGrouped` lists the row's own tap
    // handling swallows the button's `isPressed` state, so the press
    // effect never fires. We render a plain surface and drive the
    // pressed state ourselves via `_PressState` — that gives us the
    // exact same scale + opacity dip as `ComposeBarButtonStyle`,
    // visibly, on every tap.
    PressableSurface(action: {
      HapticManager.shared.light()
      onTap()
    }) {
      // Symmetric padding on all four sides keeps the card balanced —
      // the dot strip and the header sit equidistant from each edge.
      // Internal spacing is one tier tighter than the outer padding so
      // the title and dot zones still read as paired (label above,
      // data below) without the card feeling top-heavy.
      VStack(alignment: .leading, spacing: Spacing.large) {
        header
        weekStrip
      }
      .padding(Spacing.large)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityAddTraits(.isButton)
  }

  // MARK: - Header

  /// "This week" + "See all >" header. Uses Dynamic Type tokens
  /// throughout so the row scales with user accessibility settings:
  ///   • Title: `.headline` — 17pt semibold by default.
  ///   • Affordance + chevron: `.callout` regular weight in secondary
  ///     color. Same weight on text and chevron so the pair reads as
  ///     one phrase.
  private var header: some View {
    HStack {
      Text(LocalizedStringKey(Localizable.reflectionsThisWeek))
        .font(.headline)
        .foregroundColor(Color.theme.textPrimary)

      Spacer()

      HStack(alignment: .firstTextBaseline, spacing: Spacing.xxSmall) {
        Text(LocalizedStringKey(Localizable.reflectionsSeeAll))
          .font(.callout)
          .foregroundColor(Color.theme.textSecondary)
        Image(systemName: "chevron.right")
          .font(.footnote)
          .foregroundColor(Color.theme.textSecondary)
      }
    }
  }

  // MARK: - Week strip

  private var weekStrip: some View {
    let week = currentWeekDays
    return HStack(spacing: 0) {
      ForEach(Array(week.enumerated()), id: \.offset) { index, day in
        column(for: day)
          .frame(width: dotSize)
        if index < week.count - 1 {
          Spacer(minLength: 0)
        }
      }
    }
  }

  /// One day column: weekday letter on top, dot in the middle, tiny
  /// today-marker dot underneath. Sized exactly to the dot so the parent
  /// HStack can space the columns evenly between the leading and trailing
  /// edges of the card.
  private func column(for day: WeekDay) -> some View {
    VStack(spacing: Spacing.xSmall) {
      Text(WeekdaySymbols.veryShort(for: day.date,
                                    calendar: languageManager.calendar,
                                    locale: languageManager.locale))
        .font(.caption.weight(.medium))
        .foregroundColor(Color.theme.textTertiary)

      dot(for: day)

      // Tiny "today" indicator under the dot — visible only on today's column.
      Circle()
        .fill(day.isToday ? Color.theme.accentPrimary : Color.clear)
        .frame(width: todayMarkerSize, height: todayMarkerSize)
    }
  }

  @ViewBuilder
  private func dot(for day: WeekDay) -> some View {
    let calendar = languageManager.calendar
    let isFuture = day.date > calendar.startOfDay(for: Date())
    let isReflected = reflectedDays.contains(day.date)

    ZStack {
      if isReflected {
        Circle()
          .fill(Color.theme.backgroundTertiary)
        Image("reflection_smiley")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .foregroundStyle(Color.theme.textPrimary)
          .frame(width: dotSize * 0.7, height: dotSize * 0.7)
          .offset(y: 3)
      } else {
        Circle()
          .fill(Color.theme.backgroundTertiary)
          .opacity(isFuture ? 0.5 : 1.0)
      }
    }
    .frame(width: dotSize, height: dotSize)
  }

  // MARK: - Week computation

  fileprivate struct WeekDay {
    let date: Date
    let isToday: Bool
  }

  private var currentWeekDays: [WeekDay] {
    let calendar = languageManager.calendar
    let today = calendar.startOfDay(for: Date())

    guard
      let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today)
    else {
      return []
    }

    let weekStart = calendar.startOfDay(for: weekInterval.start)
    return (0..<7).compactMap { offset -> WeekDay? in
      guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart)
      else { return nil }
      let day = calendar.startOfDay(for: date)
      return WeekDay(date: day, isToday: day == today)
    }
  }

  // MARK: - Accessibility

  private var accessibilityLabel: String {
    let count = currentWeekDays.filter { reflectedDays.contains($0.date) }.count
    return appLocalizedString(Localizable.reflectionsBannerA11y, arguments: count)
  }
}

// MARK: - PressableSurface

/// A tappable surface that visibly responds to press inside `List` rows.
///
/// `Button` + `ButtonStyle` doesn't reliably show a custom press effect
/// when the button is the entire content of an `.insetGrouped` row —
/// the row's own gesture recognizer wins and the `isPressed` state never
/// flips. We use a `DragGesture` with `minimumDistance: 0` to track
/// finger-down / finger-up directly, and a `TapGesture` to fire the
/// action. Animation values match `ComposeBarButtonStyle` exactly:
/// 0.985 scale, 0.92 opacity, ease-out 0.18s.
private struct PressableSurface<Content: View>: View {
  let action: () -> Void
  @ViewBuilder let content: Content

  @State private var isPressed = false

  var body: some View {
    content
      .scaleEffect(isPressed ? 0.985 : 1.0)
      .opacity(isPressed ? 0.92 : 1.0)
      .animation(.easeOut(duration: 0.18), value: isPressed)
      .contentShape(Rectangle())
      // DragGesture(minimumDistance: 0) tracks finger-down immediately
      // and gives us a release callback. We don't act on drag distance
      // — the TapGesture below owns the action so a finger that drifts
      // off the surface still cancels the press visual but doesn't
      // accidentally fire.
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in
            if !isPressed { isPressed = true }
          }
          .onEnded { _ in
            isPressed = false
          }
      )
      .simultaneousGesture(
        TapGesture().onEnded { action() }
      )
  }
}

#Preview {
  List {
    Section {
      WeekReflectionBanner(
        reflectedDays: {
          let cal = Calendar(identifier: .gregorian)
          let today = cal.startOfDay(for: Date())
          return Set([today,
                      cal.date(byAdding: .day, value: -1, to: today)!,
                      cal.date(byAdding: .day, value: -3, to: today)!])
        }(),
        onTap: {}
      )
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.theme.backgroundSecondary)
      .listRowSeparator(.hidden)
    }
  }
  .listStyle(.insetGrouped)
  .scrollContentBackground(.hidden)
  .background(Color.theme.backgroundPrimary)
  .environmentObject(LanguageManager.shared)
}

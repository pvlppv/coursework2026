import SwiftUI

// MARK: - Date Grouping Logic

enum DateGroup: String, CaseIterable {
  case today = "Today"
  case yesterday = "Yesterday"
  case thisWeek = "ThisWeek"
  case lastWeek = "LastWeek"
  case thisMonth = "ThisMonth"
  case lastMonth = "LastMonth"
  case older = "Older"
  // Note: rawValues are used only for stable ID generation in DateGroupInfo.
}

struct DateGroupInfo: Identifiable {
  let id: String  // Stable unique ID for SwiftUI diffing
  let group: DateGroup
  let title: String
  let entries: [Entry]
  let date: Date

  init(group: DateGroup, title: String, entries: [Entry], date: Date) {
    // Combine group rawValue + timestamp for guaranteed uniqueness
    self.id = "\(group.rawValue)_\(Int(date.timeIntervalSince1970))"
    self.group = group
    self.title = title
    self.entries = entries
    self.date = date
  }
}

// MARK: - Grouped Entries View
// Note: This view provides content for a List (not a standalone VStack).
// The parent (HomeView) wraps this in a List with .listStyle(.insetGrouped).

struct GroupedEntriesView: View {
  let entries: [Entry]
  let onTapEntry: (Entry) -> Void
  let onDeleteEntry: (Entry) -> Void

  @EnvironmentObject private var languageManager: LanguageManager

  // Compute groups on demand without caching in @State
  // SwiftUI will handle performance optimization automatically
  private var groupedEntries: [DateGroupInfo] {
    computeGroupedEntries()
  }

  private func computeGroupedEntries() -> [DateGroupInfo] {
    guard !entries.isEmpty else { return [] }

    let calendar = languageManager.calendar
    let now = Date()

    // Use startOfDay for stable section IDs.
    // Raw Date() changes every second, causing DateGroupInfo.id to change
    // on every body re-evaluation, which makes SwiftUI treat sections as NEW
    // and triggers full layout recalculation (the "layout jump" bug).
    let startOfToday = calendar.startOfDay(for: now)
    let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday

    // Calculate boundary dates once
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
    let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
    let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfWeek) ?? now
    let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
    let lastMonthStart = calendar.dateInterval(of: .month, for: lastMonth)?.start ?? lastMonth

    // Single-pass classification: each entry evaluated once via if-else chain
    var todayBucket: [Entry] = []
    var yesterdayBucket: [Entry] = []
    var thisWeekBucket: [Entry] = []
    var lastWeekBucket: [Entry] = []
    var thisMonthBucket: [Entry] = []
    var lastMonthBucket: [Entry] = []
    var olderBucket: [Entry] = []

    for entry in entries {
      if calendar.isDate(entry.date, inSameDayAs: now) {
        todayBucket.append(entry)
      } else if calendar.isDate(entry.date, inSameDayAs: yesterday) {
        yesterdayBucket.append(entry)
      } else if entry.date >= startOfWeek {
        thisWeekBucket.append(entry)
      } else if entry.date >= lastWeekStart {
        lastWeekBucket.append(entry)
      } else if entry.date >= startOfMonth {
        thisMonthBucket.append(entry)
      } else if entry.date >= lastMonthStart {
        lastMonthBucket.append(entry)
      } else {
        olderBucket.append(entry)
      }
    }

    // Assemble groups from classified buckets
    var groups: [DateGroupInfo] = []

    if !todayBucket.isEmpty {
      groups.append(
        DateGroupInfo(
          group: .today,
          title: appLocalizedString(Localizable.today),
          entries: todayBucket.sorted { $0.date > $1.date },
          date: startOfToday  // Stable: midnight today
        ))
    }

    if !yesterdayBucket.isEmpty {
      groups.append(
        DateGroupInfo(
          group: .yesterday,
          title: appLocalizedString(Localizable.yesterday),
          entries: yesterdayBucket.sorted { $0.date > $1.date },
          date: startOfYesterday  // Stable: midnight yesterday
        ))
    }

    if !thisWeekBucket.isEmpty {
      groups.append(
        DateGroupInfo(
          group: .thisWeek,
          title: appLocalizedString(Localizable.thisWeek),
          entries: thisWeekBucket.sorted { $0.date > $1.date },
          date: startOfWeek
        ))
    }

    if !lastWeekBucket.isEmpty {
      groups.append(
        DateGroupInfo(
          group: .lastWeek,
          title: appLocalizedString(Localizable.lastWeek),
          entries: lastWeekBucket.sorted { $0.date > $1.date },
          date: lastWeekStart
        ))
    }

    if !thisMonthBucket.isEmpty {
      let monthTitle = DateFormatter.formatMonthName(now)
      let capitalizedTitle = monthTitle.prefix(1).uppercased() + monthTitle.dropFirst()
      groups.append(
        DateGroupInfo(
          group: .thisMonth,
          title: capitalizedTitle,
          entries: thisMonthBucket.sorted { $0.date > $1.date },
          date: startOfMonth
        ))
    }

    if !lastMonthBucket.isEmpty {
      let rawTitle: String
      if DateFormatter.isSameYear(now, lastMonth) {
        rawTitle = DateFormatter.formatMonthName(lastMonth)
      } else {
        rawTitle = DateFormatter.formatMonthNameWithYear(lastMonth)
      }
      let capitalizedTitle = rawTitle.prefix(1).uppercased() + rawTitle.dropFirst()
      groups.append(
        DateGroupInfo(
          group: .lastMonth,
          title: capitalizedTitle,
          entries: lastMonthBucket.sorted { $0.date > $1.date },
          date: lastMonthStart
        ))
    }

    // Older entries: sub-group by month
    if !olderBucket.isEmpty {
      let olderGrouped = Dictionary(grouping: olderBucket) { entry in
        calendar.dateInterval(of: .month, for: entry.date)?.start ?? entry.date
      }

      for (monthDate, monthEntries) in olderGrouped.sorted(by: { $0.key > $1.key }) {
        let rawTitle: String
        if DateFormatter.isSameYear(now, monthDate) {
          rawTitle = DateFormatter.formatMonthName(monthDate)
        } else {
          rawTitle = DateFormatter.formatMonthNameWithYear(monthDate)
        }
        let capitalizedTitle = rawTitle.prefix(1).uppercased() + rawTitle.dropFirst()
        groups.append(
          DateGroupInfo(
            group: .older,
            title: capitalizedTitle,
            entries: monthEntries.sorted { $0.date > $1.date },
            date: monthDate
          ))
      }
    }

    return groups
  }

  var body: some View {
    if entries.isEmpty {
      emptyState
    } else {
      entriesList
    }
  }

  private var entriesList: some View {
    ForEach(groupedEntries) { groupInfo in
      Section {
        ForEach(groupInfo.entries) { entry in
          entryRow(entry: entry)
        }
      } header: {
        sectionHeader(title: groupInfo.title)
      }
      .headerProminence(.increased)
    }
  }

  private func entryRow(entry: Entry) -> some View {
    EntryCard(
      entry: entry,
      onTap: {
        onTapEntry(entry)
      }
    )
    .id(entry.id)
    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    .listRowBackground(Color.theme.backgroundSecondary)
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button {
        HapticManager.shared.light()
        onDeleteEntry(entry)
      } label: {
        Label(String(localized: "delete", bundle: Bundle.main), systemImage: "trash")
      }
      .tint(.red)
    }
  }

  private func sectionHeader(title: String) -> some View {
    dateGroupHeadline(title)
  }

  private func dateGroupHeadline(_ title: String) -> some View {
    Text(title)
      .textCase(nil)
      .padding(.leading, -Spacing.medium) // insetGrouped aligns headers with row content; shift to card edge
  }

  private var emptyState: some View {
    EmptyStateView(
      icon: "pencil.line",
      title: "empty_state_title",
      description: "empty_state_description"
    )
  }
}

#Preview {
  GroupedEntriesView(
    entries: [],
    onTapEntry: { _ in },
    onDeleteEntry: { _ in }
  )
  .environment(\.theme, Theme())
  .environmentObject(LanguageManager.shared)
}

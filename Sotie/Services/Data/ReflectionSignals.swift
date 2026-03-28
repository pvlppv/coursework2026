import Foundation

/// Computes the set of calendar days on which the user "reflected".
///
/// A day counts as a reflection day if any of the following happened on that
/// day (in the active calendar's local time):
///   • The user created a new `Entry` (`entry.date` falls on the day)
///   • The user typed a Go Deeper reply on any entry (a `DialogueMessage`
///     with `role == .user` whose `timestamp` falls on the day)
///
/// We deliberately don't count AI-only events (assistant replies, follow-up
/// notifications) — the signal should reflect the user's actual presence and
/// participation, not the system reaching out.
struct ReflectionSignals {

  /// Day → number of distinct reflection events on that day. Currently used
  /// only to know whether the day "lit up", but kept as a count so future
  /// surfaces (e.g. heatmap intensity) don't need a second pass over data.
  typealias DailyMap = [Date: Int]

  /// Returns the set of `startOfDay` dates that count as reflection days.
  ///
  /// - Parameters:
  ///   - entries: all entries to scan.
  ///   - calendar: calendar used to bucket dates (defaults to LanguageManager).
  @MainActor
  static func reflectedDays(
    from entries: [Entry],
    calendar: Calendar? = nil
  ) -> Set<Date> {
    let resolvedCalendar = calendar ?? LanguageManager.shared.calendar
    return Set(dailyCounts(from: entries, calendar: resolvedCalendar).keys)
  }

  /// Returns a day → count map. Each entry contributes 1 to its creation day,
  /// and each user-authored dialogue message contributes 1 to the day it was
  /// sent. Multiple events on the same day stack into the count.
  @MainActor
  static func dailyCounts(
    from entries: [Entry],
    calendar: Calendar? = nil
  ) -> DailyMap {
    let resolvedCalendar = calendar ?? LanguageManager.shared.calendar
    var counts: DailyMap = [:]

    for entry in entries {
      // Creation day always counts as a reflection touchpoint.
      let creationDay = resolvedCalendar.startOfDay(for: entry.date)
      counts[creationDay, default: 0] += 1

      // Each user-authored Go Deeper reply on a possibly-different day
      // also counts as a reflection on that day.
      for message in entry.conversation where message.role == .user {
        let messageDay = resolvedCalendar.startOfDay(for: message.timestamp)
        // Skip the duplicate when the message is the seed observation written
        // on the entry's creation day (we already counted creation).
        if messageDay == creationDay { continue }
        counts[messageDay, default: 0] += 1
      }
    }

    return counts
  }
}

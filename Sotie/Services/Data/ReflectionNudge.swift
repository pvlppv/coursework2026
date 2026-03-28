import Foundation

/// State-aware copy that sits under the streak tiles in the reflections
/// calendar sheet. Six states keyed off `(currentStreak, bestStreak)`:
///
/// - `.firstTime`     — never reflected at all
/// - `.returning`     — currently 0, but has reflected before
/// - `.dayOne`        — exactly 1 day in
/// - `.earlyMomentum` — 2…4 days
/// - `.weekRhythm`    — 5…13 days
/// - `.practice`      — 14+ days
///
/// Why this shape: the goal isn't to motivate via gym-bro hype, it's to
/// reflect the user's actual signal back to them in a way that lands as
/// "noticed" rather than "instructed." Copy is observation-first, with
/// invitations instead of commands — Sotie's TOV is "no advice, just the
/// right question," and these lines deliberately stay on that side of
/// the line.
///
/// Pure value type, no side effects, no I/O — fast enough to compute on
/// every render.
enum ReflectionNudge {

  case firstTime
  case returning
  case dayOne
  case earlyMomentum
  case weekRhythm
  case practice

  /// Pick the right state from streak signals.
  ///
  /// `bestStreak == 0` is our "ever reflected?" signal. It's correct
  /// because `bestStreak` is computed from the same `reflectedDays` set
  /// that powers the tiles, so a non-zero best streak guarantees at
  /// least one historical reflection.
  static func resolve(currentStreak: Int, bestStreak: Int) -> ReflectionNudge {
    if currentStreak == 0 {
      return bestStreak == 0 ? .firstTime : .returning
    }
    switch currentStreak {
    case 1: return .dayOne
    case 2...4: return .earlyMomentum
    case 5...13: return .weekRhythm
    default: return .practice
    }
  }

  /// Localization key in `Localizable.strings`. Resolved through the
  /// app's `Localizable` table the same way the rest of the
  /// `reflections_*` keys are.
  var localizationKey: String {
    switch self {
    case .firstTime:     return Localizable.reflectionsNudgeFirstTime
    case .returning:     return Localizable.reflectionsNudgeReturning
    case .dayOne:        return Localizable.reflectionsNudgeDayOne
    case .earlyMomentum: return Localizable.reflectionsNudgeEarlyMomentum
    case .weekRhythm:    return Localizable.reflectionsNudgeWeekRhythm
    case .practice:      return Localizable.reflectionsNudgePractice
    }
  }
}

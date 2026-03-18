import Combine
import Foundation
import SwiftUI

@MainActor
final class LanguageManager: ObservableObject {
  static let shared = LanguageManager()
  nonisolated static let appLanguageKey = "AppLanguage"
  /// Set to true the moment the user picks a language from inside the app
  /// (Settings > Language or the onboarding language picker). When false,
  /// the app follows iOS Settings > Sotie > Preferred Language so the two
  /// don't drift apart silently.
  nonisolated static let explicitAppLanguageChoiceKey = "AppLanguageWasUserSelected"

  @Published var currentLanguage: Language
  @Published var locale: Locale
  @Published var timeZone: TimeZone
  @Published var calendar: Calendar

  private init() {
    let storedCode = UserDefaults.standard.string(forKey: Self.appLanguageKey)
    let userPickedExplicitly = UserDefaults.standard.bool(forKey: Self.explicitAppLanguageChoiceKey)

    let resolvedLanguage = Self.resolveInitialLanguage(
      storedLanguageCode: userPickedExplicitly ? storedCode : nil,
      preferredLanguages: Locale.preferredLanguages
    )
    let resolvedLocale = Self.locale(for: resolvedLanguage, regionLocale: .autoupdatingCurrent)

    self.currentLanguage = resolvedLanguage
    self.locale = resolvedLocale
    self.timeZone = TimeZone.current

    var newCalendar = Calendar(identifier: .gregorian)
    newCalendar.locale = resolvedLocale
    self.calendar = newCalendar

    // Keep the stored code in sync so the rest of the app (backend AI requests,
    // notifications, etc.) reads the same value via `storedOrDefaultLanguageCode()`.
    if storedCode != resolvedLanguage.code {
      UserDefaults.standard.set(resolvedLanguage.code, forKey: Self.appLanguageKey)
    }
  }

  func setLanguage(_ language: Language) {
    currentLanguage = language
    locale = Self.locale(for: language, regionLocale: .autoupdatingCurrent)

    var newCalendar = Calendar(identifier: .gregorian)
    newCalendar.locale = locale
    calendar = newCalendar

    UserDefaults.standard.set(language.code, forKey: Self.appLanguageKey)
    // Mark this as an explicit user choice so future launches honor it
    // instead of falling back to iOS Settings.
    UserDefaults.standard.set(true, forKey: Self.explicitAppLanguageChoiceKey)
  }

  func pluralize(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
    if currentLanguage == .russian {
      let mod10 = count % 10
      let mod100 = count % 100

      if mod100 >= 11 && mod100 <= 14 {
        return many
      } else if mod10 == 1 {
        return one
      } else if mod10 >= 2 && mod10 <= 4 {
        return few
      } else {
        return many
      }
    }

    return count == 1 ? one : many
  }

  nonisolated func getLanguageCode() -> String {
    Self.storedOrDefaultLanguageCode()
  }

  nonisolated static func storedOrDefaultLanguageCode() -> String {
    // If the user explicitly picked a language from inside the app, honor it.
    // Otherwise follow iOS Settings (Settings > Sotie > Preferred Language)
    // so the AI and notifications don't drift away from what the user sees
    // in the OS-level language preference.
    let userPickedExplicitly = UserDefaults.standard.bool(forKey: explicitAppLanguageChoiceKey)
    if userPickedExplicitly,
       let storedCode = UserDefaults.standard.string(forKey: appLanguageKey),
       let language = Language(code: storedCode) {
      return language.code
    }

    let resolved = resolveInitialLanguage(
      storedLanguageCode: nil,
      preferredLanguages: Locale.preferredLanguages
    )
    return resolved.code
  }

  nonisolated static func locale(forLanguageCode languageCode: String, regionLocale: Locale) -> Locale {
    guard let language = Language(code: languageCode) else {
      return locale(for: .english, regionLocale: regionLocale)
    }

    return locale(for: language, regionLocale: regionLocale)
  }

  nonisolated static func englishLocale(for regionLocale: Locale) -> Locale {
    locale(for: .english, regionLocale: regionLocale)
  }

  nonisolated static func resolveInitialLanguage(
    storedLanguageCode: String?,
    preferredLanguages: [String]
  ) -> Language {
    if let storedLanguageCode, let storedLanguage = Language(code: storedLanguageCode) {
      return storedLanguage
    }

    for preferredLanguage in preferredLanguages {
      if let preferred = Language(code: preferredLanguage) {
        return preferred
      }

      let locale = Locale(identifier: preferredLanguage)
      if let languageCode = locale.language.languageCode?.identifier,
        let preferred = Language(code: languageCode)
      {
        return preferred
      }
    }

    return .english
  }

  nonisolated private static func locale(for language: Language, regionLocale: Locale) -> Locale {
    guard let regionCode = regionLocale.region?.identifier, language.preservesDeviceRegion else {
      return Locale(identifier: language.localeIdentifier)
    }

    return Locale(identifier: "\(language.localeIdentifier)_\(regionCode)")
  }
}

enum LanguageScript: Sendable {
  case latin
  case cyrillic
  case japanese
  case korean
  case chineseSimplified
}

enum Language: String, CaseIterable, Identifiable, Sendable {
  case english = "en"
  case russian = "ru"
  case spanish = "es"
  case portuguese = "pt"
  case french = "fr"
  case german = "de"
  case italian = "it"
  case japanese = "ja"
  case korean = "ko"
  case simplifiedChinese = "zh-Hans"

  nonisolated var id: String { code }

  nonisolated init?(code: String) {
    let normalized = code
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: "-")

    switch normalized {
    case "en", "en-us", "en-gb": self = .english
    case "ru", "ru-ru": self = .russian
    case "es", "es-es", "es-419", "es-mx": self = .spanish
    case "pt", "pt-br", "pt-pt": self = .portuguese
    case "fr", "fr-fr", "fr-ca": self = .french
    case "de", "de-de": self = .german
    case "it", "it-it": self = .italian
    case "ja", "ja-jp": self = .japanese
    case "ko", "ko-kr": self = .korean
    case "zh", "zh-cn", "zh-sg", "zh-hans", "zh-hans-cn": self = .simplifiedChinese
    default: return nil
    }
  }

  nonisolated var code: String { rawValue }

  nonisolated var localeIdentifier: String {
    switch self {
    case .simplifiedChinese:
      return "zh-Hans"
    default:
      return code
    }
  }

  nonisolated var aiLanguageName: String {
    switch self {
    case .english: return "English"
    case .russian: return "Russian"
    case .spanish: return "Spanish"
    case .portuguese: return "Portuguese"
    case .french: return "French"
    case .german: return "German"
    case .italian: return "Italian"
    case .japanese: return "Japanese"
    case .korean: return "Korean"
    case .simplifiedChinese: return "Simplified Chinese"
    }
  }

  nonisolated var localizedName: String {
    switch self {
    case .english: return "English"
    case .russian: return "Русский"
    case .spanish: return "Español"
    case .portuguese: return "Português"
    case .french: return "Français"
    case .german: return "Deutsch"
    case .italian: return "Italiano"
    case .japanese: return "日本語"
    case .korean: return "한국어"
    case .simplifiedChinese: return "简体中文"
    }
  }

  /// Country-flag emoji used as a quick visual recognition cue in language
  /// pickers (onboarding + Settings). Languages don't strictly map to a single
  /// country, so the choice is pragmatic: most-recognizable flag for each.
  nonisolated var flag: String {
    switch self {
    case .english: return "🇬🇧"
    case .russian: return "🇷🇺"
    case .spanish: return "🇪🇸"
    case .portuguese: return "🇵🇹"
    case .french: return "🇫🇷"
    case .german: return "🇩🇪"
    case .italian: return "🇮🇹"
    case .japanese: return "🇯🇵"
    case .korean: return "🇰🇷"
    case .simplifiedChinese: return "🇨🇳"
    }
  }

  /// Two-letter uppercase code shown next to the flag in the compact onboarding
  /// language switcher. Always uppercased, region-independent.
  nonisolated var shortCode: String {
    switch self {
    case .english: return "EN"
    case .russian: return "RU"
    case .spanish: return "ES"
    case .portuguese: return "PT"
    case .french: return "FR"
    case .german: return "DE"
    case .italian: return "IT"
    case .japanese: return "JA"
    case .korean: return "KO"
    case .simplifiedChinese: return "ZH"
    }
  }

  nonisolated var script: LanguageScript {
    switch self {
    case .english, .spanish, .portuguese, .french, .german, .italian:
      return .latin
    case .russian:
      return .cyrillic
    case .japanese:
      return .japanese
    case .korean:
      return .korean
    case .simplifiedChinese:
      return .chineseSimplified
    }
  }

  nonisolated var preservesDeviceRegion: Bool {
    switch self {
    case .simplifiedChinese:
      return false
    default:
      return true
    }
  }
}

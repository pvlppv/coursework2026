import Foundation

/// Shared language utility used by backend AI request builders and notification validation.
/// Single source of truth for language resolution — avoids duplication.
enum LanguageDetector {

  nonisolated static func uiLanguage() -> (code: String, name: String) {
    let languageCode = LanguageManager.storedOrDefaultLanguageCode()
    let language = Language(code: languageCode) ?? .english
    return (language.code, language.aiLanguageName)
  }
}

import Foundation
import Testing

@testable import Sotie

@MainActor
struct LocalizationCoverageTests {

  private static let localizableStringsPath = repoRootURL
    .appendingPathComponent("Sotie")
    .appendingPathComponent("Resources")
    .appendingPathComponent("en.lproj")
    .appendingPathComponent("Localizable.strings")

  private static let localizationRegistryPath = repoRootURL
    .appendingPathComponent("Sotie")
    .appendingPathComponent("Resources")
    .appendingPathComponent("Localization.swift")

  private static let infoPlistPath = repoRootURL
    .appendingPathComponent("Sotie")
    .appendingPathComponent("Info.plist")

  private static let englishInfoPlistStringsPath = repoRootURL
    .appendingPathComponent("Sotie")
    .appendingPathComponent("Resources")
    .appendingPathComponent("en.lproj")
    .appendingPathComponent("InfoPlist.strings")

  private static let russianInfoPlistStringsPath = repoRootURL
    .appendingPathComponent("Sotie")
    .appendingPathComponent("Resources")
    .appendingPathComponent("ru.lproj")
    .appendingPathComponent("InfoPlist.strings")

  private static let expectedInfoPlistLocalizationDirectories = [
    "de.lproj",
    "en.lproj",
    "es.lproj",
    "fr.lproj",
    "it.lproj",
    "ja.lproj",
    "ko.lproj",
    "pt.lproj",
    "ru.lproj",
    "zh-Hans.lproj",
  ]

  private static let expectedLocalizableDirectories = [
    "de.lproj",
    "en.lproj",
    "es.lproj",
    "fr.lproj",
    "it.lproj",
    "ja.lproj",
    "ko.lproj",
    "pt.lproj",
    "ru.lproj",
    "zh-Hans.lproj",
  ]

  @Test func englishLocalePreservesDeviceRegion() async throws {
    let locale = LanguageManager.englishLocale(for: Locale(identifier: "fr_FR"))

    #expect(locale.language.languageCode?.identifier == "en")
    #expect(locale.region?.identifier == "FR")
  }

  @Test func initialLanguageUsesStoredSupportedLanguageBeforeDevicePreference() async throws {
    let resolved = LanguageManager.resolveInitialLanguage(
      storedLanguageCode: "ru",
      preferredLanguages: ["en-US"]
    )

    #expect(resolved == .russian)
  }

  @Test func initialLanguageUsesDevicePreferenceOnFirstLaunch() async throws {
    let resolved = LanguageManager.resolveInitialLanguage(
      storedLanguageCode: nil,
      preferredLanguages: ["ru-RU", "en-US"]
    )

    #expect(resolved == .russian)
  }

  @Test func initialLanguageFallsBackToEnglishForUnsupportedDeviceLanguage() async throws {
    let resolved = LanguageManager.resolveInitialLanguage(
      storedLanguageCode: nil,
      preferredLanguages: ["nl-NL"]
    )

    #expect(resolved == .english)
  }

  @Test func languageDetectorResolvesToStoredLanguage() async throws {
    UserDefaults.standard.set("ru", forKey: "AppLanguage")
    defer { UserDefaults.standard.removeObject(forKey: "AppLanguage") }

    let language = LanguageDetector.uiLanguage()

    #expect(language.code == "ru")
    #expect(language.name == Language.russian.aiLanguageName)
  }

  @Test func sharedLanguageResolutionDefaultsToEnglish() async throws {
    UserDefaults.standard.removeObject(forKey: LanguageManager.appLanguageKey)

    #expect(LanguageManager.storedOrDefaultLanguageCode() == "en")
  }

  @Test func sharedLanguageResolutionFallsBackForUnknownStoredValue() async throws {
    UserDefaults.standard.set("xx", forKey: LanguageManager.appLanguageKey)
    defer { UserDefaults.standard.removeObject(forKey: LanguageManager.appLanguageKey) }

    #expect(LanguageManager.storedOrDefaultLanguageCode() == "en")
  }

  @Test func sharedLanguageResolutionReturnsStoredSupportedLanguage() async throws {
    UserDefaults.standard.set("ru", forKey: LanguageManager.appLanguageKey)
    defer { UserDefaults.standard.removeObject(forKey: LanguageManager.appLanguageKey) }

    #expect(LanguageManager.storedOrDefaultLanguageCode() == "ru")
  }

  @Test func fallbackQuestionsSwitchWithLanguageCode() async throws {
    let englishQuestions = NotificationContentTemplate.fallbackQuestions(
      for: .conversationFollowUp,
      languageCode: "en"
    )
    let russianQuestions = NotificationContentTemplate.fallbackQuestions(
      for: .conversationFollowUp,
      languageCode: "ru"
    )

    #expect(!englishQuestions.isEmpty)
    #expect(!russianQuestions.isEmpty)
    #expect(englishQuestions.contains(localizedString(Localizable.notificationFollowUpFallback, languageCode: "en")))
    #expect(russianQuestions.contains(localizedString(Localizable.notificationFollowUpFallback, languageCode: "ru")))
  }

  @Test func appShipsSelectedLocalizationResources() async throws {
    let resourcesURL = Self.repoRootURL
      .appendingPathComponent("Sotie")
      .appendingPathComponent("Resources")

    let localizedDirectories = try FileManager.default.contentsOfDirectory(
      at: resourcesURL,
      includingPropertiesForKeys: nil
    )
    .filter { $0.lastPathComponent.hasSuffix(".lproj") }
    .map(\.lastPathComponent)
    .sorted()

    #expect(localizedDirectories == Self.expectedInfoPlistLocalizationDirectories)
  }

  @Test func appShipsLocalizedInfoPlistStringsForSelectedLanguages() async throws {
    for directory in Self.expectedInfoPlistLocalizationDirectories {
      let infoPlistStringsPath = Self.repoRootURL
        .appendingPathComponent("Sotie")
        .appendingPathComponent("Resources")
        .appendingPathComponent(directory)
        .appendingPathComponent("InfoPlist.strings")
      let localizedInfoPlistStrings = try String(contentsOf: infoPlistStringsPath, encoding: .utf8)

      #expect(localizedInfoPlistStrings.contains("NSUserNotificationsUsageDescription"))
    }
  }

  @Test func infoPlistDoesNotHardcodeAppleLanguagesOrNotificationUsageCopy() async throws {
    let infoPlist = try String(contentsOf: Self.infoPlistPath, encoding: .utf8)

    #expect(!infoPlist.contains("<key>AppleLanguages</key>"))
    #expect(!infoPlist.contains("We use notifications to help you stay on track with your entries"))
  }

  @Test func localizationRegistryMatchesEnglishStringsKeys() async throws {
    let stringsFile = try String(contentsOf: Self.localizableStringsPath, encoding: .utf8)
    let registryFile = try String(contentsOf: Self.localizationRegistryPath, encoding: .utf8)

    let stringsKeys = Set(extractMatches(in: stringsFile, pattern: #"\"([^\"]+)\"\s*="#))
    let registryKeys = Set(
      extractMatches(in: registryFile, pattern: #"static let \w+\s*=\s*\"([^\"]+)\""#)
    )

    #expect(stringsKeys == registryKeys)
  }

  @Test func russianStringsCoverLocalizationRegistryKeys() async throws {
    let stringsFile = try String(
      contentsOf: Self.repoRootURL
        .appendingPathComponent("Sotie")
        .appendingPathComponent("Resources")
        .appendingPathComponent("ru.lproj")
        .appendingPathComponent("Localizable.strings"),
      encoding: .utf8
    )
    let registryFile = try String(contentsOf: Self.localizationRegistryPath, encoding: .utf8)

    let stringsKeys = Set(extractMatches(in: stringsFile, pattern: #"\"([^\"]+)\"\s*="#))
    let registryKeys = Set(
      extractMatches(in: registryFile, pattern: #"static let \w+\s*=\s*\"([^\"]+)\""#)
    )

    #expect(registryKeys.isSubset(of: stringsKeys))
  }

  @Test func allSelectedLanguagesCoverLocalizationRegistryKeys() async throws {
    let resourcesURL = Self.repoRootURL
      .appendingPathComponent("Sotie")
      .appendingPathComponent("Resources")

    let localizableDirectories = try FileManager.default.contentsOfDirectory(
      at: resourcesURL,
      includingPropertiesForKeys: nil
    )
    .filter { fileURL in
      fileURL.lastPathComponent.hasSuffix(".lproj")
        && FileManager.default.fileExists(atPath: fileURL.appendingPathComponent("Localizable.strings").path)
    }
    .map(\.lastPathComponent)
    .sorted()

    #expect(localizableDirectories == Self.expectedLocalizableDirectories)
  }

  @Test func verifiedUiStringsAreLocalizedInsteadOfHardCoded() async throws {
    let forbiddenLiteralsByFile: [String: [String]] = [
      "Views/HomeView.swift": ["Add Entry"],
      "Views/PrototypeHomeView.swift": ["Add new entry", "Done", "Today", "Yesterday", "This Week", "Last Week"],
      "Views/Detail/EntryComponents/AddEntryView.swift": ["Journal entry"],
      "Views/Detail/EntryComponents/EditEntryView.swift": ["Journal entry"],
      "Views/Conversation/InlineConversationView.swift": [
        "Reply to reflection"
      ],
      "Views/Onboarding/Steps/OnboardingConversationView.swift": ["Journal entry"],
      "Views/PreferencesSheet.swift": ["Contact", "Legal"],
      "Resources/DateFormatter.swift": ["Today", "Yesterday"],
    ]

    for (relativePath, forbiddenLiterals) in forbiddenLiteralsByFile {
      let fileURL = Self.repoRootURL
        .appendingPathComponent("Sotie")
        .appendingPathComponent(relativePath)
      let fileContents = try String(contentsOf: fileURL, encoding: .utf8)

      for forbiddenLiteral in forbiddenLiterals {
        let forbiddenQuotedLiteral = "\"\(forbiddenLiteral)\""
        #expect(
          !fileContents.contains(forbiddenQuotedLiteral),
          "Expected \(relativePath) to localize \(forbiddenLiteral) instead of hard-coding it as a string literal."
        )
      }
    }
  }

  @Test func notificationTypeLocalizationKeysExistForAllNotificationCases() async throws {
    let stringsFile = try String(contentsOf: Self.localizableStringsPath, encoding: .utf8)
    let stringsKeys = Set(extractMatches(in: stringsFile, pattern: #"\"([^\"]+)\"\s*="#))

    for notificationType in NotificationType.allCases {
      #expect(stringsKeys.contains(notificationType.titleKey))
      #expect(stringsKeys.contains(notificationType.descriptionKey))
    }
  }

  @Test func appViewsDoNotUseLegacyLocalizedHelpers() async throws {
    let viewsURL = Self.repoRootURL
      .appendingPathComponent("Sotie")
      .appendingPathComponent("Views")

    let enumerator = FileManager.default.enumerator(
      at: viewsURL,
      includingPropertiesForKeys: nil
    )

    var offendingFiles: [String] = []

    while let fileURL = enumerator?.nextObject() as? URL {
      guard fileURL.pathExtension == "swift" else { continue }

      let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
      if fileContents.contains(".localized(") || fileContents.contains("LocalizedKeys.") {
        offendingFiles.append(fileURL.lastPathComponent)
      }
    }

    #expect(
      offendingFiles.isEmpty,
      "Expected SwiftUI view files to use native localization APIs only, but found legacy helper usage in: \(offendingFiles.sorted().joined(separator: ", "))."
    )
  }

  private static var repoRootURL: URL {
    let testFileURL = URL(fileURLWithPath: #filePath)
    return testFileURL.deletingLastPathComponent().deletingLastPathComponent()
  }

  private func extractMatches(in text: String, pattern: String) -> [String] {
    let regex = try? NSRegularExpression(pattern: pattern)
    let range = NSRange(text.startIndex..., in: text)

    return regex?.matches(in: text, range: range).compactMap { match in
      guard let captureRange = Range(match.range(at: 1), in: text) else { return nil }
      return String(text[captureRange])
    } ?? []
  }
}

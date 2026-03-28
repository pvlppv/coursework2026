import Foundation
import NaturalLanguage

enum AILanguageValidationResult: String, Sendable {
  case accept
  case uncertain
  case reject
}

enum AILanguageValidator {

  nonisolated static func validateResponse(
    _ text: String,
    targetLanguageCode: String
  ) -> AILanguageValidationResult {
    validateText(text, targetLanguageCode: targetLanguageCode)
  }

  nonisolated static func validateQuestion(
    _ text: String,
    targetLanguageCode: String
  ) -> AILanguageValidationResult {
    validateText(text, targetLanguageCode: targetLanguageCode)
  }

  private nonisolated static func validateText(
    _ text: String,
    targetLanguageCode: String
  ) -> AILanguageValidationResult {
    guard let targetLanguage = Language(code: targetLanguageCode) else { return .uncertain }

    let normalizedText = normalizedValidationText(from: text)
    let lettersCount = normalizedText.unicodeScalars.filter { $0.properties.isAlphabetic }.count

    guard lettersCount >= 4 else { return .uncertain }

    let recognizer = NLLanguageRecognizer()
    recognizer.processString(normalizedText)

    let targetNLLanguages = Set(targetLanguage.nlLanguages)
    let hypotheses = recognizer.languageHypotheses(withMaximum: 3)

    guard !hypotheses.isEmpty else { return .uncertain }

    if let targetConfidence = targetNLLanguages.compactMap({ hypotheses[$0] }).max(), targetConfidence >= 0.35 {
      return .accept
    }

    if let (bestLanguage, bestConfidence) = hypotheses.max(by: { $0.value < $1.value }),
      !targetNLLanguages.contains(bestLanguage),
      bestConfidence >= 0.75
    {
      return .reject
    }

    return .uncertain
  }

  private nonisolated static func normalizedValidationText(from text: String) -> String {
    meaningfulTokens(in: text)
      .joined(separator: " ")
  }

  private nonisolated static func meaningfulTokens(in text: String) -> [String] {
    text
      .split(whereSeparator: \.isWhitespace)
      .compactMap { rawToken in
        let original = String(rawToken)
        let cleaned = original.trimmingCharacters(in: aiLanguageNoise)

        guard !cleaned.isEmpty else { return nil }
        guard !cleaned.contains("://"), !cleaned.hasPrefix("www.") else { return nil }
        guard !cleaned.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) else {
          return nil
        }
        guard cleaned.unicodeScalars.contains(where: { $0.properties.isAlphabetic }) else { return nil }
        guard !isShortAcronym(cleaned) else { return nil }

        return cleaned
      }
  }

  private nonisolated static func isShortAcronym(_ token: String) -> Bool {
    guard token.count <= 5 else { return false }
    let letters = token.filter(\.isLetter)
    guard !letters.isEmpty else { return false }
    return letters == letters.uppercased()
  }
}

private nonisolated let aiLanguageNoise = CharacterSet.punctuationCharacters
  .union(.symbols)
  .union(.whitespacesAndNewlines)

private extension Language {
  nonisolated var nlLanguages: [NLLanguage] {
    switch self {
    case .english:
      return [.english]
    case .russian:
      return [.russian]
    case .spanish:
      return [.spanish]
    case .portuguese:
      return [.portuguese]
    case .french:
      return [.french]
    case .german:
      return [.german]
    case .italian:
      return [.italian]
    case .japanese:
      return [.japanese]
    case .korean:
      return [.korean]
    case .simplifiedChinese:
      return [.simplifiedChinese, .traditionalChinese]
    }
  }
}

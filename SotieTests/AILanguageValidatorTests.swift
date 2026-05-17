import Foundation
import Testing

@testable import Sotie

struct AILanguageValidatorTests {

  @Test func acceptsEnglishQuestionForEnglishTarget() {
    let result = AILanguageValidator.validateQuestion(
      "What keeps hurting now?",
      targetLanguageCode: Language.english.code
    )

    #expect(result.rawValue == AILanguageValidationResult.accept.rawValue)
  }

  @Test func acceptsRussianQuestionForRussianTarget() {
    let result = AILanguageValidator.validateQuestion(
      "Что продолжает болеть сейчас?",
      targetLanguageCode: Language.russian.code
    )

    #expect(result.rawValue == AILanguageValidationResult.accept.rawValue)
  }

  @Test func rejectsClearlyWrongScriptForRussianTarget() {
    let result = AILanguageValidator.validateQuestion(
      "What keeps hurting now?",
      targetLanguageCode: Language.russian.code
    )

    #expect(result.rawValue == AILanguageValidationResult.reject.rawValue)
  }

  @Test func staysUncertainForVeryShortQuestion() {
    let result = AILanguageValidator.validateQuestion(
      "Why?",
      targetLanguageCode: Language.english.code
    )

    #expect(result.rawValue == AILanguageValidationResult.uncertain.rawValue)
  }

  @Test func ignoresUrlAndAcronymNoise() {
    let result = AILanguageValidator.validateQuestion(
      "https://t.me GPT?",
      targetLanguageCode: Language.russian.code
    )

    #expect(result.rawValue == AILanguageValidationResult.uncertain.rawValue)
  }

  @Test func acceptsSpanishQuestionForSpanishTarget() {
    let result = AILanguageValidator.validateQuestion(
      "¿Qué sigue pesando ahora?",
      targetLanguageCode: Language.spanish.code
    )

    #expect(result.rawValue == AILanguageValidationResult.accept.rawValue)
  }

  @Test func acceptsJapaneseQuestionForJapaneseTarget() {
    let result = AILanguageValidator.validateQuestion(
      "今も引っかかっているのは何？",
      targetLanguageCode: Language.japanese.code
    )

    #expect(result.rawValue == AILanguageValidationResult.accept.rawValue)
  }

  @Test func acceptsChineseQuestionForChineseTarget() {
    let result = AILanguageValidator.validateQuestion(
      "现在最卡住你的是什么？",
      targetLanguageCode: Language.simplifiedChinese.code
    )

    #expect(result.rawValue == AILanguageValidationResult.accept.rawValue)
  }
}

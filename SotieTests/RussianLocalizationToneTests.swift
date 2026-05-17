import Foundation
import Testing

struct RussianLocalizationToneTests {

  @Test func russianSelectedStringsUseNeutralOrInformalCopy() async throws {
    let strings = try Self.loadRussianStrings()

    #expect(
      strings["delete_entry_message"] == "Удалить эту запись? Это действие нельзя отменить.")
    #expect(strings["onboarding_tap_continue"] == "Нажми, когда захочешь продолжить")
    #expect(
      strings["premium_response_limit_reached_desc"]
        == "You can go deeper. Unlock unlimited reflection and keep your self-discovery moving."
    )
  }

  private static func loadRussianStrings() throws -> [String: String] {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repoRootURL = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
    let stringsURL = repoRootURL
      .appendingPathComponent("Sotie")
      .appendingPathComponent("Resources")
      .appendingPathComponent("ru.lproj")
      .appendingPathComponent("Localizable.strings")

    let contents = try String(contentsOf: stringsURL, encoding: .utf8)
    var result: [String: String] = [:]

    let pattern = #"\"([^\"]+)\"\s*=\s*\"((?:\\.|[^\"\\])*)\";"#
    let regex = try NSRegularExpression(pattern: pattern)
    let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)

    for match in regex.matches(in: contents, range: range) {
      guard
        let keyRange = Range(match.range(at: 1), in: contents),
        let valueRange = Range(match.range(at: 2), in: contents)
      else {
        continue
      }

      let key = String(contents[keyRange])
      let value = String(contents[valueRange])
        .replacingOccurrences(of: #"\""#, with: #"""#)
        .replacingOccurrences(of: #"\n"#, with: "\n")
      result[key] = value
    }

    return result
  }
}

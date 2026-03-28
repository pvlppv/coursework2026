//
//  OpenAIStreamingEventParser.swift
//  Sotie
//

import Foundation

enum OpenAIStreamingEvent {
  case content(String)
  case done
  case failure(OpenAIClientError)
  case ignore
}

enum OpenAIStreamingEventParser {
  nonisolated static func parse(_ line: String) -> OpenAIStreamingEvent {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

    guard trimmed.hasPrefix("data:") else {
      return .ignore
    }

    let jsonString = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)

    if jsonString == "[DONE]" {
      return .done
    }

    guard let data = jsonString.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return .ignore
    }

    if let error = parseStreamingError(json) {
      return .failure(error)
    }

    guard let choices = json["choices"] as? [[String: Any]],
      let delta = choices.first?["delta"] as? [String: Any],
      let content = delta["content"] as? String,
      !content.isEmpty
    else {
      return .ignore
    }

    return .content(content)
  }

  private nonisolated static func parseStreamingError(_ json: [String: Any]) -> OpenAIClientError? {
    if let error = json["error"] as? [String: Any] {
      let message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      let code = error["code"] as? Int
      let status = (error["metadata"] as? [String: Any])?["raw"] as? Int

      if let message, !message.isEmpty {
        return .apiError(message, code ?? status ?? 500)
      }
    }

    if let choices = json["choices"] as? [[String: Any]],
      let choice = choices.first,
      let finishReason = choice["finish_reason"] as? String,
      finishReason == "error"
    {
      let message = (choice["message"] as? [String: Any])?["content"] as? String
      return .apiError(message ?? "Streaming request failed", 500)
    }

    return nil
  }
}

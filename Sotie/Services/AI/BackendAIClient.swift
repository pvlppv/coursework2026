//
//  BackendAIClient.swift
//  Sotie
//

import Foundation
import os

final class BackendAIClient: @unchecked Sendable {
  private let backend: BackendClient
  private let session: URLSession
  private let streamResponseTimeout: TimeInterval
  private let jsonResponseTimeout: TimeInterval

  nonisolated init(
    backend: BackendClient? = nil,
    session: URLSession? = nil,
    streamResponseTimeout: TimeInterval = 20,
    jsonResponseTimeout: TimeInterval = 25
  ) {
    self.backend = backend ?? BackendClient.shared
    self.streamResponseTimeout = streamResponseTimeout
    self.jsonResponseTimeout = jsonResponseTimeout
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.default
      configuration.timeoutIntervalForRequest = 15
      configuration.timeoutIntervalForResource = 60
      configuration.waitsForConnectivity = true
      self.session = URLSession(configuration: configuration)
    }
  }

  nonisolated func summarizeConversation(
    coreEntryText: String,
    newMessages: [DialogueMessage],
    previousSummary: ConversationSummary?,
    totalSummarizedCount: Int,
    totalMessageCount: Int
  ) async throws -> ConversationSummary {
    let languageName = LanguageDetector.uiLanguage().name
    let suspiciousEnvironment = await SecurityManager.shared.currentRuntimeState().isSuspiciousEnvironment
    let payload: [String: Any] = [
      "coreEntryText": coreEntryText,
      "newMessages": dialogueMessagesJSONArray(newMessages),
      "previousSummary": try previousSummary.map { try currentSummaryJSONObject($0) } ?? NSNull(),
      "totalSummarizedCount": totalSummarizedCount,
      "totalMessageCount": totalMessageCount,
      "locale": ["languageName": languageName],
      "client": ["suspiciousEnvironment": suspiciousEnvironment],
    ]

    let response: BackendContentResponse<SummarizationPayload> = try await postJSON(
      path: "v1/ai/summarize-conversation",
      payload: payload
    )

    return ConversationSummary(
      coreEntryText: coreEntryText,
      coreInsight: response.content.coreInsight,
      nextOpenings: response.content.nextOpenings,
      routingState: response.content.routingState,
      responseGuidance: response.content.responseGuidance,
      stopSignals: response.content.stopSignals,
      failedAngles: response.content.failedAngles,
      signalQuality: SignalQuality(rawValue: response.content.signalQuality) ?? .moderate,
      anglesCovered: response.content.anglesCovered,
      evidenceTail: response.content.evidenceTail,
      summarizedMessageCount: totalSummarizedCount,
      totalMessageCount: totalMessageCount
    )
  }

  nonisolated func generateInsights(
    entryText: String,
    messages: [DialogueMessage]
  ) async throws -> ConversationInsights {
    let languageName = LanguageDetector.uiLanguage().name
    let suspiciousEnvironment = await SecurityManager.shared.currentRuntimeState().isSuspiciousEnvironment
    let payload: [String: Any] = [
      "entryText": entryText,
      "messages": dialogueMessagesJSONArray(messages),
      "locale": ["languageName": languageName],
      "client": ["suspiciousEnvironment": suspiciousEnvironment],
    ]
    let response: BackendContentResponse<InsightsPayload> = try await postJSON(path: "v1/ai/insights", payload: payload)
    let insights = ConversationInsights(
      whatHappened: response.content.whatHappened.trimmingCharacters(in: .whitespacesAndNewlines),
      whatsUnderneath: response.content.whatsUnderneath.trimmingCharacters(in: .whitespacesAndNewlines),
      whatMattersNow: response.content.whatMattersNow.trimmingCharacters(in: .whitespacesAndNewlines),
      messageCount: messages.count
    )
    guard !insights.whatHappened.isEmpty,
      !insights.whatsUnderneath.isEmpty,
      !insights.whatMattersNow.isEmpty
    else {
      throw InsightsError.emptyInsights
    }
    return insights
  }

  nonisolated func repairLanguage(
    originalResponse: String,
    languageName: String
  ) async throws -> String {
    let suspiciousEnvironment = await SecurityManager.shared.currentRuntimeState().isSuspiciousEnvironment
    let payload: [String: Any] = [
      "originalResponse": originalResponse,
      "locale": ["languageName": languageName],
      "client": ["suspiciousEnvironment": suspiciousEnvironment],
    ]
    let response: LanguageRepairResponse = try await postJSON(path: "v1/ai/language-repair", payload: payload)
    return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @discardableResult
  nonisolated func generateGoDeeperResponseStream(
    entryId: String,
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary?,
    seedLensHint: String?,
    onChunk: @escaping (String) -> Void
  ) async throws -> ConversationSummary? {
    let sessionStartedAt = CFAbsoluteTimeGetCurrent()
    var request = try await backend.authorizedRequest(path: "v1/ai/go-deeper/stream")
    let sessionMs = Int((CFAbsoluteTimeGetCurrent() - sessionStartedAt) * 1000)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let bodyStartedAt = CFAbsoluteTimeGetCurrent()
    request.httpBody = try await makeRequestBody(
      entryId: entryId,
      entryText: entryText,
      conversationHistory: conversationHistory,
      currentSummary: currentSummary,
      seedLensHint: seedLensHint
    )
    let bodyMs = Int((CFAbsoluteTimeGetCurrent() - bodyStartedAt) * 1000)
    let streamRequest = request

    let requestStartedAt = CFAbsoluteTimeGetCurrent()
    let (bytes, response) = try await withTimeout(seconds: streamResponseTimeout) {
      try await self.session.bytes(for: streamRequest)
    }
    let headersReceivedMs = Int((CFAbsoluteTimeGetCurrent() - requestStartedAt) * 1000)
    guard let httpResponse = response as? HTTPURLResponse else { throw OpenAIClientError.invalidResponse }

    guard (200...299).contains(httpResponse.statusCode) else {
      var errorData = Data()
      for try await byte in bytes {
        errorData.append(byte)
        if errorData.count > 4096 { break }
      }
      throw mapBackendHTTPError(statusCode: httpResponse.statusCode, body: String(data: errorData, encoding: .utf8) ?? "")
    }

    var fullResponse = ""
    var firstTokenLogged = false
    for try await line in bytes.lines {
      switch OpenAIStreamingEventParser.parse(line) {
      case .content(let content):
        if !firstTokenLogged {
          firstTokenLogged = true
          let ttftMs = Int((CFAbsoluteTimeGetCurrent() - requestStartedAt) * 1000)
          let endToEndTtftMs = Int((CFAbsoluteTimeGetCurrent() - sessionStartedAt) * 1000)
          AppLogger.ai.info("Go Deeper stream first token: sessionMs=\(sessionMs) bodyMs=\(bodyMs) headersMs=\(headersReceivedMs) streamTtftMs=\(ttftMs) endToEndTtftMs=\(endToEndTtftMs)")
        }
        fullResponse += content
        onChunk(fullResponse)
      case .done:
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - requestStartedAt) * 1000)
        AppLogger.ai.info("Go Deeper stream completed: durationMs=\(durationMs)")
        return currentSummary
      case .failure(let error):
        throw error
      case .ignore:
        continue
      }
    }

    return currentSummary
  }

  private nonisolated func makeRequestBody(
    entryId: String,
    entryText: String,
    conversationHistory: [DialogueMessage],
    currentSummary: ConversationSummary?,
    seedLensHint: String?
  ) async throws -> Data {
    let formatter = ISO8601DateFormatter()
    let suspiciousEnvironment = await SecurityManager.shared.currentRuntimeState().isSuspiciousEnvironment

    var payload: [String: Any] = [
      "entryId": entryId,
      "entryText": entryText,
      "conversationHistory": dialogueMessagesJSONArray(conversationHistory, formatter: formatter),
      "reflectionSettings": AIReflectionSettingsStore.load().promptJSONObject,
      "locale": [
        "languageName": LanguageDetector.uiLanguage().name,
        "regionCode": (Locale.current.region?.identifier ?? NSNull()) as Any,
      ],
      "client": [
        "suspiciousEnvironment": suspiciousEnvironment,
      ],
    ]

    if let currentSummary {
      payload["currentSummary"] = try currentSummaryJSONObject(currentSummary)
    }
    if let seedLensHint, !seedLensHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      payload["seedLensHint"] = seedLensHint
    }

    return try JSONSerialization.data(withJSONObject: payload)
  }

  private nonisolated func currentSummaryJSONObject(_ summary: ConversationSummary) throws -> Any {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(summary)
    return try JSONSerialization.jsonObject(with: data)
  }

  private nonisolated func dialogueMessagesJSONArray(
    _ messages: [DialogueMessage],
    formatter: ISO8601DateFormatter = ISO8601DateFormatter()
  ) -> [[String: Any]] {
    messages.map { message in
      var item: [String: Any] = [
        "id": message.id.uuidString,
        "role": message.role.rawValue,
        "content": message.content,
        "timestamp": formatter.string(from: message.timestamp),
      ]
      if let durationMs = message.durationMs {
        item["durationMs"] = durationMs
      }
      return item
    }
  }

  private nonisolated func postJSON<T: Decodable>(path: String, payload: [String: Any]) async throws -> T {
    var request = try await backend.authorizedRequest(path: path)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    let jsonRequest = request

    let (data, response) = try await withTimeout(seconds: jsonResponseTimeout) {
      try await self.session.data(for: jsonRequest)
    }
    guard let httpResponse = response as? HTTPURLResponse else { throw OpenAIClientError.invalidResponse }

    guard (200...299).contains(httpResponse.statusCode) else {
      throw mapBackendHTTPError(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: data)
  }

  private nonisolated func mapBackendHTTPError(statusCode: Int, body: String) -> Error {
    switch statusCode {
    case 402:
      return PremiumError.responseLimitReached
    case 429:
      if let retryAfter = retryAfterSeconds(from: body) {
        return OpenAIClientError.localRateLimitExceeded(retryAfter: retryAfter)
      }
      return OpenAIClientError.rateLimitExceeded
    case 401, 403:
      return OpenAIClientError.invalidSession
    case 413:
      return OpenAIClientError.maxTokensExceeded
    case 400...499:
      return OpenAIClientError.apiError(body, statusCode)
    default:
      return OpenAIClientError.apiError(body.isEmpty ? "Backend request failed" : body, statusCode)
    }
  }

  private nonisolated func retryAfterSeconds(from body: String) -> TimeInterval? {
    guard let data = body.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let error = json["error"] as? [String: Any],
      let details = error["details"] as? [String: Any],
      let retryAfterSeconds = details["retryAfterSeconds"] as? Double
    else { return nil }

    return retryAfterSeconds
  }

  private nonisolated func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      defer { group.cancelAll() }
      group.addTask {
        try await operation()
      }
      group.addTask {
        try await Task.sleep(for: .seconds(seconds))
        throw URLError(.timedOut)
      }

      guard let result = try await group.next() else {
        throw URLError(.timedOut)
      }
      return result
    }
  }
}

private struct BackendContentResponse<T: Decodable & Sendable>: Sendable {
  let content: T
}

extension BackendContentResponse: Decodable {
  private enum CodingKeys: String, CodingKey { case content }

  nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    content = try container.decode(T.self, forKey: .content)
  }
}

private struct SummarizationPayload: Sendable {
  let signalQuality: String
  let coreInsight: String
  let routingState: String
  let responseGuidance: String
  let nextOpenings: String
  let stopSignals: [String]
  let failedAngles: [String]
  let anglesCovered: [String]
  let evidenceTail: [String]
}

extension SummarizationPayload: Decodable {
  private enum CodingKeys: String, CodingKey {
    case signalQuality, coreInsight, routingState, responseGuidance, nextOpenings, stopSignals, failedAngles, anglesCovered, evidenceTail
  }

  nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    signalQuality = try container.decode(String.self, forKey: .signalQuality)
    coreInsight = try container.decode(String.self, forKey: .coreInsight)
    routingState = try container.decode(String.self, forKey: .routingState)
    responseGuidance = try container.decode(String.self, forKey: .responseGuidance)
    nextOpenings = try container.decode(String.self, forKey: .nextOpenings)
    stopSignals = try container.decode([String].self, forKey: .stopSignals)
    failedAngles = try container.decode([String].self, forKey: .failedAngles)
    anglesCovered = try container.decode([String].self, forKey: .anglesCovered)
    evidenceTail = try container.decode([String].self, forKey: .evidenceTail)
  }
}

private struct InsightsPayload: Sendable {
  let whatHappened: String
  let whatsUnderneath: String
  let whatMattersNow: String
}

extension InsightsPayload: Decodable {
  private enum CodingKeys: String, CodingKey {
    case whatHappened = "what_happened"
    case whatsUnderneath = "whats_underneath"
    case whatMattersNow = "what_matters_now"
  }

  nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    whatHappened = try container.decode(String.self, forKey: .whatHappened)
    whatsUnderneath = try container.decode(String.self, forKey: .whatsUnderneath)
    whatMattersNow = try container.decode(String.self, forKey: .whatMattersNow)
  }
}

private struct LanguageRepairResponse: Sendable {
  let text: String
}

extension LanguageRepairResponse: Decodable {
  private enum CodingKeys: String, CodingKey { case text }

  nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    text = try container.decode(String.self, forKey: .text)
  }
}

enum InsightsError: LocalizedError {
  case emptyInsights

  var errorDescription: String? {
    switch self {
    case .emptyInsights:
      return "Generated insights were empty"
    }
  }
}

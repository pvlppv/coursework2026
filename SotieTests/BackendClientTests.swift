//
//  BackendClientTests.swift
//  SotieTests
//

import Foundation
import Testing

@testable import Sotie

@Suite(.serialized)
@MainActor
struct BackendClientTests {

  @Test func ensureSessionCreatesAndStoresToken() async throws {
    let secureStore = BackendTestSecureStore()
    let transport = BackendTestTransport()
    transport.enqueue(
      statusCode: 200,
      body: """
        {
          "token":"created-token",
          "session":{"sessionId":"session-1","installId":"install-1"},
          "entitlement":{"state":"free","productId":null,"originalTransactionId":null,"expiresAt":null,"verifiedAt":null}
        }
        """
    )

    let client = makeClient(secureStore: secureStore, transport: transport)
    let session = try await client.ensureSession()

    #expect(session.token == "created-token")
    #expect(session.session.sessionId == "session-1")
    #expect(try secureStore.string(for: "backend.session.token") == "created-token")
    #expect(transport.requests.map(\.url?.path) == ["/v1/session"])
    #expect(transport.requests.first?.httpMethod == "POST")

    let requestBody = try #require(transport.requests.first?.testBodyData)
    let json = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    #expect(json["installId"] as? String == "install-1")
  }

  @Test func ensureSessionReusesStoredTokenViaMe() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("stored-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(
      statusCode: 200,
      body: """
        {
          "session":{"sessionId":"session-existing","installId":"install-1"},
          "entitlement":{"state":"premium","productId":"premium.monthly","originalTransactionId":"original-1","expiresAt":"2026-05-22T12:00:00Z","verifiedAt":"2026-05-22T11:00:00Z"}
        }
        """
    )

    let client = makeClient(secureStore: secureStore, transport: transport)
    let session = try await client.ensureSession()

    #expect(session.token == "stored-token")
    #expect(session.entitlement.state == .premium)
    #expect(transport.requests.map(\.url?.path) == ["/v1/me"])
    #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer stored-token")
  }

  @Test func backendEntitlementMapsToSubscriptionStatus() throws {
    let trialEnd = try #require(ISO8601DateFormatter().date(from: "2026-05-22T12:00:00Z"))

    #expect(BackendEntitlement(state: .free, productId: nil, originalTransactionId: nil, expiresAt: nil, verifiedAt: nil).subscriptionStatus == nil)
    #expect(BackendEntitlement(state: .premium, productId: nil, originalTransactionId: nil, expiresAt: nil, verifiedAt: nil).subscriptionStatus == .premium)
    #expect(BackendEntitlement(state: .trial, productId: nil, originalTransactionId: nil, expiresAt: trialEnd, verifiedAt: nil).subscriptionStatus == .trial(expiresAt: trialEnd))
  }

  @Test func ensureSessionRecreatesSessionAfterStoredTokenIsUnauthorized() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("expired-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(statusCode: 401, body: #"{"error":{"code":"unauthorized","message":"Expired"}}"#)
    transport.enqueue(
      statusCode: 200,
      body: """
        {
          "token":"fresh-token",
          "session":{"sessionId":"session-fresh","installId":"install-1"},
          "entitlement":{"state":"free","productId":null,"originalTransactionId":null,"expiresAt":null,"verifiedAt":null}
        }
        """
    )

    let client = makeClient(secureStore: secureStore, transport: transport)
    let session = try await client.ensureSession()

    #expect(session.token == "fresh-token")
    #expect(try secureStore.string(for: "backend.session.token") == "fresh-token")
    #expect(transport.requests.map(\.url?.path) == ["/v1/me", "/v1/session"])
  }

  @Test func verifyTransactionSendsSignedTransactionWithBearerToken() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("stored-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(
      statusCode: 200,
      body: """
        {
          "session":{"sessionId":"session-existing","installId":"install-1"},
          "entitlement":{"state":"premium","productId":"premium.monthly","originalTransactionId":"original-1","expiresAt":"2026-05-22T12:00:00Z","verifiedAt":"2026-05-22T11:00:00Z"}
        }
        """
    )
    transport.enqueue(
      statusCode: 200,
      body: """
        {
          "entitlement":{"state":"premium","productId":"premium.annual","originalTransactionId":"original-2","expiresAt":"2026-06-22T12:00:00Z","verifiedAt":"2026-05-22T11:00:00Z"}
        }
        """
    )

    let client = makeClient(secureStore: secureStore, transport: transport)
    let entitlement = try await client.verifyTransaction(signedTransactionInfo: "signed-jws")

    #expect(entitlement.productId == "premium.annual")
    #expect(transport.requests.map(\.url?.path) == ["/v1/me", "/v1/entitlements/verify-transaction"])
    let verifyRequest = try #require(transport.requests.last)
    #expect(verifyRequest.value(forHTTPHeaderField: "Authorization") == "Bearer stored-token")

    let body = try #require(verifyRequest.testBodyData)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["signedTransactionInfo"] as? String == "signed-jws")
  }

  @Test func backendAIClientStreamsCumulativeChunks() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("stored-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(
      statusCode: 200,
      body: """
        {
          "session":{"sessionId":"session-existing","installId":"install-1"},
          "entitlement":{"state":"premium","productId":"premium.monthly","originalTransactionId":"original-1","expiresAt":"2026-05-22T12:00:00Z","verifiedAt":"2026-05-22T11:00:00Z"}
        }
        """
    )
    transport.enqueue(
      statusCode: 200,
      body: """
        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: {"choices":[{"delta":{"content":" there"}}]}

        data: [DONE]

        """
    )

    let backend = makeClient(secureStore: secureStore, transport: transport)
    let aiClient = BackendAIClient(backend: backend, session: transport.session)
    var chunks: [String] = []

    _ = try await aiClient.generateGoDeeperResponseStream(
      entryId: "entry-1",
      entryText: "I feel stuck.",
      conversationHistory: [DialogueMessage(role: .user, content: "Why do I avoid this?")],
      currentSummary: nil,
      seedLensHint: "avoidance",
      onChunk: { chunks.append($0) }
    )

    #expect(chunks == ["Hello", "Hello there"])
    #expect(transport.requests.map(\.url?.path) == ["/v1/me", "/v1/ai/go-deeper/stream"])
    let streamRequest = try #require(transport.requests.last)
    #expect(streamRequest.value(forHTTPHeaderField: "Authorization") == "Bearer stored-token")
    #expect(streamRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let body = try #require(streamRequest.testBodyData)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["entryId"] as? String == "entry-1")
    #expect(json["entryText"] as? String == "I feel stuck.")
    #expect(json["seedLensHint"] as? String == "avoidance")
  }

  @Test func backendAIClientTimesOutSlowStreamHeaders() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("stored-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(statusCode: 200, body: existingSessionBody)
    transport.enqueueDelayed(statusCode: 200, body: "data: [DONE]\n\n", delay: 0.2)

    let backend = makeClient(secureStore: secureStore, transport: transport)
    let aiClient = BackendAIClient(backend: backend, session: transport.session, streamResponseTimeout: 0.01)

    do {
      _ = try await aiClient.generateGoDeeperResponseStream(
        entryId: "entry-1",
        entryText: "I feel stuck.",
        conversationHistory: [DialogueMessage(role: .user, content: "Why do I avoid this?")],
        currentSummary: nil,
        seedLensHint: nil,
        onChunk: { _ in }
      )
      Issue.record("Expected stream timeout")
    } catch let error as URLError {
      #expect(error.code == .timedOut)
    } catch {
      Issue.record("Expected timedOut, got \(error)")
    }
  }

  @Test func backendAIClientMapsQuotaHTTPError() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("stored-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(
      statusCode: 200,
      body: """
        {
          "session":{"sessionId":"session-existing","installId":"install-1"},
          "entitlement":{"state":"free","productId":null,"originalTransactionId":null,"expiresAt":null,"verifiedAt":null}
        }
        """
    )
    transport.enqueue(statusCode: 402, body: #"{"error":{"code":"quota_exceeded","message":"Daily limit reached"}}"#)

    let backend = makeClient(secureStore: secureStore, transport: transport)
    let aiClient = BackendAIClient(backend: backend, session: transport.session)

    do {
      _ = try await aiClient.generateGoDeeperResponseStream(
        entryId: "entry-1",
        entryText: "I feel stuck.",
        conversationHistory: [],
        currentSummary: nil,
        seedLensHint: nil,
        onChunk: { _ in }
      )
      Issue.record("Expected quota error")
    } catch PremiumError.responseLimitReached {
      #expect(transport.requests.map(\.url?.path) == ["/v1/me", "/v1/ai/go-deeper/stream"])
    } catch {
      Issue.record("Expected responseLimitReached, got \(error)")
    }
  }

  @Test func backendAIClientMapsRateLimitRetryAfterFromBody() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("stored-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(statusCode: 200, body: existingSessionBody)
    transport.enqueue(
      statusCode: 429,
      body: #"{"error":{"code":"rate_limited","message":"Too fast","details":{"retryAfterSeconds":60}}}"#
    )

    let backend = makeClient(secureStore: secureStore, transport: transport)
    let aiClient = BackendAIClient(backend: backend, session: transport.session)

    do {
      _ = try await aiClient.generateGoDeeperResponseStream(
        entryId: "entry-1",
        entryText: "I feel stuck.",
        conversationHistory: [],
        currentSummary: nil,
        seedLensHint: nil,
        onChunk: { _ in }
      )
      Issue.record("Expected rate limit error")
    } catch OpenAIClientError.localRateLimitExceeded(let retryAfter) {
      #expect(retryAfter == 60)
    } catch {
      Issue.record("Expected localRateLimitExceeded, got \(error)")
    }
  }

  @Test func backendAIClientMapsAuthErrorsToInvalidSession() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("stored-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(statusCode: 200, body: existingSessionBody)
    transport.enqueue(statusCode: 401, body: #"{"error":{"code":"expired_session","message":"Session expired"}}"#)

    let backend = makeClient(secureStore: secureStore, transport: transport)
    let aiClient = BackendAIClient(backend: backend, session: transport.session)

    do {
      _ = try await aiClient.generateGoDeeperResponseStream(
        entryId: "entry-1",
        entryText: "I feel stuck.",
        conversationHistory: [],
        currentSummary: nil,
        seedLensHint: nil,
        onChunk: { _ in }
      )
      Issue.record("Expected session error")
    } catch OpenAIClientError.invalidSession {
      #expect(true)
    } catch {
      Issue.record("Expected invalidSession, got \(error)")
    }
  }

  @Test func backendAIClientSummarizesConversationThroughTypedRoute() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("stored-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(statusCode: 200, body: existingSessionBody)
    transport.enqueue(
      statusCode: 200,
      body: #"{"content":{"signalQuality":"moderate","coreInsight":"You feel stuck.","routingState":"topic: myself","responseGuidance":"Clarify gently.","nextOpenings":"Name one next step.","stopSignals":[],"failedAngles":[],"anglesCovered":["avoidance"],"evidenceTail":["I feel stuck"]}}"#
    )

    let backend = makeClient(secureStore: secureStore, transport: transport)
    let aiClient = BackendAIClient(backend: backend, session: transport.session)
    let summary = try await aiClient.summarizeConversation(
      coreEntryText: "I feel stuck.",
      newMessages: [DialogueMessage(role: .user, content: "I keep avoiding it.")],
      previousSummary: nil,
      totalSummarizedCount: 1,
      totalMessageCount: 1
    )

    #expect(summary.coreInsight == "You feel stuck.")
    #expect(summary.signalQuality == .moderate)
    #expect(transport.requests.map(\.url?.path) == ["/v1/me", "/v1/ai/summarize-conversation"])
    let body = try #require(transport.requests.last?.testBodyData)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["coreEntryText"] as? String == "I feel stuck.")
    #expect(json["newMessages"] != nil)
    #expect(json["previousSummary"] is NSNull)
  }

  @Test func backendAIClientGeneratesInsightsThroughTypedRoute() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("stored-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(statusCode: 200, body: existingSessionBody)
    transport.enqueue(
      statusCode: 200,
      body: #"{"content":{"what_happened":"A thing happened.","whats_underneath":"It stung.","what_matters_now":"One step is clear."}}"#
    )

    let backend = makeClient(secureStore: secureStore, transport: transport)
    let aiClient = BackendAIClient(backend: backend, session: transport.session)
    let insights = try await aiClient.generateInsights(
      entryText: "I feel stuck.",
      messages: [DialogueMessage(role: .user, content: "I keep avoiding it.")]
    )

    #expect(insights.whatHappened == "A thing happened.")
    #expect(insights.messageCount == 1)
    #expect(transport.requests.map(\.url?.path) == ["/v1/me", "/v1/ai/insights"])
  }

  @Test func backendAIClientTimesOutSlowInsightsResponse() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("stored-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(statusCode: 200, body: existingSessionBody)
    transport.enqueueDelayed(
      statusCode: 200,
      body: #"{"content":{"what_happened":"A thing happened.","whats_underneath":"It stung.","what_matters_now":"One step is clear."}}"#,
      delay: 0.2
    )

    let backend = makeClient(secureStore: secureStore, transport: transport)
    let aiClient = BackendAIClient(backend: backend, session: transport.session, jsonResponseTimeout: 0.01)

    do {
      _ = try await aiClient.generateInsights(
        entryText: "I feel stuck.",
        messages: [DialogueMessage(role: .user, content: "I keep avoiding it.")]
      )
      Issue.record("Expected insights timeout")
    } catch let error as URLError {
      #expect(error.code == .timedOut)
    } catch {
      Issue.record("Expected timedOut, got \(error)")
    }
  }

  @Test func backendAIClientRepairsLanguageThroughTypedRoute() async throws {
    let secureStore = BackendTestSecureStore()
    try secureStore.set("stored-token", for: "backend.session.token")
    let transport = BackendTestTransport()
    transport.enqueue(statusCode: 200, body: existingSessionBody)
    transport.enqueue(statusCode: 200, body: #"{"text":"Repaired response."}"#)

    let backend = makeClient(secureStore: secureStore, transport: transport)
    let aiClient = BackendAIClient(backend: backend, session: transport.session)
    let text = try await aiClient.repairLanguage(originalResponse: "Wrong language.", languageName: "English")

    #expect(text == "Repaired response.")
    #expect(transport.requests.map(\.url?.path) == ["/v1/me", "/v1/ai/language-repair"])
  }

  private func makeClient(
    secureStore: SecureValueStore,
    transport: BackendTestTransport
  ) -> BackendClient {
    BackendClient(
      secureStore: secureStore,
      baseURL: URL(string: "https://backend.test")!,
      session: transport.session,
      installIdProvider: { "install-1" }
    )
  }
}

private let existingSessionBody = """
  {
    "session":{"sessionId":"session-existing","installId":"install-1"},
    "entitlement":{"state":"premium","productId":"premium.monthly","originalTransactionId":"original-1","expiresAt":"2026-05-22T12:00:00Z","verifiedAt":"2026-05-22T11:00:00Z"}
  }
  """

private final class BackendTestSecureStore: @unchecked Sendable, SecureValueStore {
  private let lock = NSLock()
  private var values: [String: Data] = [:]

  func data(for account: String) throws -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return values[account]
  }

  func set(_ data: Data, for account: String, accessible: CFString?) throws {
    lock.lock()
    defer { lock.unlock() }
    values[account] = data
  }

  func removeValue(for account: String) throws {
    lock.lock()
    defer { lock.unlock() }
    values.removeValue(forKey: account)
  }
}

private final class BackendTestTransport: @unchecked Sendable {
  struct Response: Sendable {
    let statusCode: Int
    let body: Data
    var delay: TimeInterval = 0
  }

  private let lock = NSLock()
  private var responses: [Response] = []
  private var capturedRequests: [BackendTestRequest] = []
  private let protocolClass: BackendTestURLProtocol.Type

  init() {
    protocolClass = BackendTestURLProtocol.makeSubclass()
    protocolClass.handler = { [weak self] request in
      guard let self else { throw URLError(.badServerResponse) }
      return try self.handle(request)
    }
  }

  deinit {
    protocolClass.handler = nil
  }

  var session: URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [protocolClass]
    return URLSession(configuration: configuration)
  }

  var requests: [BackendTestRequest] {
    lock.lock()
    defer { lock.unlock() }
    return capturedRequests
  }

  func enqueue(statusCode: Int, body: String) {
    lock.lock()
    defer { lock.unlock() }
    responses.append(Response(statusCode: statusCode, body: Data(body.utf8)))
  }

  func enqueueDelayed(statusCode: Int, body: String, delay: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    responses.append(Response(statusCode: statusCode, body: Data(body.utf8), delay: delay))
  }

  private func handle(_ request: URLRequest) throws -> Response {
    lock.lock()
    defer { lock.unlock() }
    capturedRequests.append(BackendTestRequest(request: request))
    guard !responses.isEmpty else { throw URLError(.badServerResponse) }
    return responses.removeFirst()
  }
}

private struct BackendTestRequest: Sendable {
  let url: URL?
  let httpMethod: String?
  let testBodyData: Data?
  private let headerFields: [String: String]

  init(request: URLRequest) {
    url = request.url
    httpMethod = request.httpMethod
    testBodyData = request.httpBody ?? request.httpBodyStream?.remainingData
    headerFields = request.allHTTPHeaderFields ?? [:]
  }

  func value(forHTTPHeaderField field: String) -> String? {
    headerFields.first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
  }
}

private extension InputStream {
  var remainingData: Data? {
    open()
    defer { close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while hasBytesAvailable {
      let count = read(&buffer, maxLength: buffer.count)
      if count < 0 { return nil }
      if count == 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

private class BackendTestURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> BackendTestTransport.Response)?

  class func makeSubclass() -> BackendTestURLProtocol.Type {
    final class Subclass: BackendTestURLProtocol, @unchecked Sendable {}
    return Subclass.self
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    do {
      guard let handler = Self.handler else { throw URLError(.badServerResponse) }
      let testResponse = try handler(request)
      if testResponse.delay > 0 {
        Thread.sleep(forTimeInterval: testResponse.delay)
      }
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: testResponse.statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: testResponse.body)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

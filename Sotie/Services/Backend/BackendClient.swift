//
//  BackendClient.swift
//  Sotie
//

import Foundation
import os
import Security

struct BackendSession: Codable, Sendable {
  let token: String
  let session: BackendSessionInfo
  let entitlement: BackendEntitlement
}

struct BackendSessionInfo: Codable, Sendable {
  let sessionId: String
  let installId: String
}

struct BackendEntitlement: Codable, Sendable {
  enum State: String, Codable, Sendable {
    case free
    case trial
    case premium
  }

  let state: State
  let productId: String?
  let originalTransactionId: String?
  let expiresAt: Date?
  let verifiedAt: Date?
}

extension BackendEntitlement {
  var subscriptionStatus: SubscriptionStatus? {
    switch state {
    case .free:
      return nil
    case .trial:
      return .trial(expiresAt: expiresAt ?? .distantFuture)
    case .premium:
      return .premium
    }
  }
}

enum BackendError: LocalizedError {
  case notConfigured
  case invalidResponse
  case missingSession
  case apiError(code: String, message: String, statusCode: Int)

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "Sotie backend is not configured."
    case .invalidResponse:
      return "Invalid response from Sotie backend."
    case .missingSession:
      return "Sotie backend session is missing."
    case .apiError(_, let message, let statusCode):
      return "Backend error (\(statusCode)): \(message)"
    }
  }
}

final class BackendClient: @unchecked Sendable {
  nonisolated static let shared = BackendClient()

  private enum StorageKey {
    static let sessionToken = "backend.session.token"
  }

  private let session: URLSession
  private let secureStore: SecureValueStore
  private let baseURLOverride: URL?
  private let installIdProvider: @Sendable () async -> String
  private let jsonEncoder: JSONEncoder
  private let jsonDecoder: JSONDecoder
  private let lock = NSLock()
  private var cachedToken: String?

  init(
    secureStore: SecureValueStore? = nil,
    baseURL: URL? = nil,
    session: URLSession? = nil,
    installIdProvider: (@Sendable () async -> String)? = nil
  ) {
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.default
      configuration.timeoutIntervalForRequest = 15
      configuration.timeoutIntervalForResource = 60
      configuration.waitsForConnectivity = true
      self.session = URLSession(configuration: configuration)
    }
    self.secureStore = secureStore ?? KeychainService.shared
    self.baseURLOverride = baseURL
    self.installIdProvider = installIdProvider ?? { await SecurityManager.shared.persistentInstallationID() }
    self.jsonEncoder = JSONEncoder()
    self.jsonDecoder = JSONDecoder()
    self.jsonEncoder.dateEncodingStrategy = .iso8601
    self.jsonDecoder.dateDecodingStrategy = .iso8601
  }

  var isConfigured: Bool { resolvedBaseURL != nil }

  func ensureSession() async throws -> BackendSession {
    guard let baseURL = resolvedBaseURL else { throw BackendError.notConfigured }
    let startedAt = CFAbsoluteTimeGetCurrent()

    if let token = storedToken {
      do {
        let me: MeResponse = try await send(
          request: URLRequest(url: baseURL.appendingPathComponent("v1/me")),
          bearerToken: token
        )
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        AppLogger.ai.info("Backend session ready: source=cached validationMs=\(durationMs)")
        return BackendSession(token: token, session: me.session, entitlement: me.entitlement)
      } catch BackendError.apiError(_, _, let statusCode) where statusCode == 401 {
        clearStoredToken()
      }
    }

    var request = URLRequest(url: baseURL.appendingPathComponent("v1/session"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try await jsonEncoder.encode(SessionRequest(installId: installIdProvider()))

    let created: BackendSession = try await send(request: request, bearerToken: nil)
    storeToken(created.token)
    let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
    AppLogger.ai.info("Backend session ready: source=created creationMs=\(durationMs)")
    return created
  }

  func verifyTransaction(signedTransactionInfo: String) async throws -> BackendEntitlement {
    guard let baseURL = resolvedBaseURL else { throw BackendError.notConfigured }
    let session = try await ensureSession()

    var request = URLRequest(url: baseURL.appendingPathComponent("v1/entitlements/verify-transaction"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try jsonEncoder.encode(VerifyTransactionRequest(signedTransactionInfo: signedTransactionInfo))

    let response: EntitlementResponse = try await send(request: request, bearerToken: session.token)
    return response.entitlement
  }

  func authorizedRequest(path: String) async throws -> URLRequest {
    guard let baseURL = resolvedBaseURL else { throw BackendError.notConfigured }
    let session = try await ensureSession()
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
    return request
  }

  private var storedToken: String? {
    lock.lock()
    if let cachedToken {
      lock.unlock()
      return cachedToken
    }
    lock.unlock()

    let token = try? secureStore.string(for: StorageKey.sessionToken)

    lock.lock()
    cachedToken = token
    lock.unlock()

    return token
  }

  private var resolvedBaseURL: URL? {
    baseURLOverride ?? BackendConfig.baseURL
  }

  private func storeToken(_ token: String) {
    lock.lock()
    cachedToken = token
    lock.unlock()

    do {
      try secureStore.set(token, for: StorageKey.sessionToken, accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    } catch {
      AppLogger.app.error("Failed to persist backend session token: \(error)")
    }
  }

  private func clearStoredToken() {
    lock.lock()
    cachedToken = nil
    lock.unlock()
    try? secureStore.removeValue(for: StorageKey.sessionToken)
  }

  private func send<T: Decodable>(request originalRequest: URLRequest, bearerToken: String?) async throws -> T {
    var request = originalRequest
    if let bearerToken {
      request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else { throw BackendError.invalidResponse }

    guard (200...299).contains(httpResponse.statusCode) else {
      let apiError = try? jsonDecoder.decode(BackendAPIErrorEnvelope.self, from: data)
      throw BackendError.apiError(
        code: apiError?.error.code ?? "backend_error",
        message: apiError?.error.message ?? "Backend request failed",
        statusCode: httpResponse.statusCode
      )
    }

    return try jsonDecoder.decode(T.self, from: data)
  }
}

private struct SessionRequest: Codable {
  let installId: String
}

private struct MeResponse: Codable {
  let session: BackendSessionInfo
  let entitlement: BackendEntitlement
}

private struct VerifyTransactionRequest: Codable {
  let signedTransactionInfo: String
}

private struct EntitlementResponse: Codable {
  let entitlement: BackendEntitlement
}

private struct BackendAPIErrorEnvelope: Codable {
  struct APIError: Codable {
    let code: String
    let message: String
  }

  let error: APIError
}

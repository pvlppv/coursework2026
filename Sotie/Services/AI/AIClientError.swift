//
//  AIClientError.swift
//  Sotie
//

import Foundation

enum OpenAIClientError: LocalizedError {
  case invalidAPIKey
  case invalidSession
  case networkError(Error)
  case decodingError(DecodingError)
  case apiError(String, Int)
  case rateLimitExceeded
  case localRateLimitExceeded(retryAfter: TimeInterval)
  case maxTokensExceeded
  case invalidResponse
  case noContent
  case unknownError

  var errorDescription: String? {
    switch self {
    case .invalidAPIKey:
      return "Invalid API key. Please check your configuration."
    case .invalidSession:
      return "Your session expired. Please try again."
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .decodingError(let error):
      return "Failed to decode response: \(error.localizedDescription)"
    case .apiError(let message, let code):
      return "API error (\(code)): \(message)"
    case .rateLimitExceeded:
      return "Rate limit exceeded. Please wait a moment before trying again."
    case .localRateLimitExceeded(let retryAfter):
      return "Too many AI requests too quickly. Please try again in \(Int(retryAfter.rounded(.up))) seconds."
    case .maxTokensExceeded:
      return "Response was too long. This has been fixed — please try again."
    case .invalidResponse:
      return "Invalid response format received from the AI service."
    case .noContent:
      return "No content received from the AI service."
    case .unknownError:
      return "An unknown error occurred with the AI service."
    }
  }
}

/// Maps any AI-related error to a localized user-facing string and an optional
/// retry-after interval. Use this instead of `error.localizedDescription` in UI code.
///
/// - Returns: `(message, retryAfter)` where `retryAfter` is non-nil only when the
///   caller should block further requests until `Date() + retryAfter`.
func userFacingAIError(from error: Error) -> (message: String, retryAfter: TimeInterval?) {
  if let clientError = error as? OpenAIClientError {
    switch clientError {
    case .localRateLimitExceeded(let retryAfter):
      return (appLocalizedString(Localizable.errorRateLimited, arguments: Int(retryAfter.rounded(.up))), retryAfter)
    case .rateLimitExceeded:
      return (appLocalizedString(Localizable.errorRateLimited, arguments: 60), 60)
    case .networkError(let underlyingError):
      if isConnectivityError(underlyingError) {
        return (appLocalizedString(Localizable.errorNetwork), nil)
      }
      return (appLocalizedString(Localizable.errorAIService), nil)
    default:
      return (appLocalizedString(Localizable.errorAIService), nil)
    }
  }

  if isConnectivityError(error) {
    return (appLocalizedString(Localizable.errorNetwork), nil)
  }

  if case AIServiceError.ttftTimeout = error {
    return (appLocalizedString(Localizable.errorAIService), nil)
  }

  if error is CancellationError {
    return (appLocalizedString(Localizable.errorAIService), nil)
  }

  return (appLocalizedString(Localizable.errorAIService), nil)
}

private func isConnectivityError(_ error: Error) -> Bool {
  let urlErrorCode: URLError.Code?

  if let urlError = error as? URLError {
    urlErrorCode = urlError.code
  } else if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain {
    urlErrorCode = URLError.Code(rawValue: nsError.code)
  } else {
    urlErrorCode = nil
  }

  guard let code = urlErrorCode else { return false }

  switch code {
  case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost:
    return true
  default:
    return false
  }
}

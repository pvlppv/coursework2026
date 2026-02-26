//
//  BackendConfig.swift
//  Sotie
//

import Foundation

enum BackendConfig {
  /// Set `SOTIE_BACKEND_BASE_URL` in Info.plist/build settings for production.
  /// Debug defaults to production so simulator smoke tests exercise the deployed backend.
  nonisolated static var baseURL: URL? {
    if let value = Bundle.main.object(forInfoDictionaryKey: "SOTIE_BACKEND_BASE_URL") as? String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty || trimmed == "$(SOTIE_BACKEND_BASE_URL)" {
        return debugFallbackURL
      }
      guard let url = URL(string: trimmed) else { return debugFallbackURL }
      return url
    }

    return debugFallbackURL
  }

  private nonisolated static var debugFallbackURL: URL? {
    #if DEBUG
      return URL(string: "https://sotie.app")
    #else
      return nil
    #endif
  }

  nonisolated static var isEnabled: Bool {
    baseURL != nil
  }
}

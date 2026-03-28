//
//  KeychainService.swift
//  Sotie
//
//  Created by Codex on 08.03.2026.
//

import Foundation
import Security

protocol SecureValueStore: Sendable {
  nonisolated
  func data(for account: String) throws -> Data?
  nonisolated
  func set(_ data: Data, for account: String, accessible: CFString?) throws
  nonisolated
  func removeValue(for account: String) throws
}

extension SecureValueStore {
  nonisolated
  func string(for account: String) throws -> String? {
    guard let data = try data(for: account) else { return nil }
    guard let value = String(data: data, encoding: .utf8) else {
      throw KeychainError.invalidStringData
    }
    return value
  }

  nonisolated
  func set(_ value: String, for account: String, accessible: CFString? = nil) throws {
    try set(Data(value.utf8), for: account, accessible: accessible)
  }

  nonisolated
  func codable<T: Decodable>(_ type: T.Type, for account: String) throws -> T? {
    guard let data = try data(for: account) else { return nil }
    return try JSONDecoder().decode(type, from: data)
  }

  nonisolated
  func setCodable<T: Encodable>(_ value: T, for account: String, accessible: CFString? = nil)
    throws
  {
    let data = try JSONEncoder().encode(value)
    try set(data, for: account, accessible: accessible)
  }
}

enum KeychainError: LocalizedError {
  case invalidStringData
  case unexpectedStatus(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidStringData:
      return "Keychain data could not be decoded as UTF-8."
    case .unexpectedStatus(let status):
      return "Keychain operation failed with status \(status)."
    }
  }
}

final class KeychainService: @unchecked Sendable, SecureValueStore {
  nonisolated static let shared = KeychainService(
    service: (Bundle.main.bundleIdentifier ?? "com.pvlppv.sotie.journal") + ".shared"
  )

  nonisolated static let usage = KeychainService(
    service: (Bundle.main.bundleIdentifier ?? "com.pvlppv.sotie.journal") + ".usage",
    defaultAccessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  )

  private let service: String
  private nonisolated(unsafe) let defaultAccessibility: CFString

  nonisolated init(
    service: String,
    defaultAccessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  ) {
    self.service = service
    self.defaultAccessibility = defaultAccessibility
  }

  nonisolated func data(for account: String) throws -> Data? {
    var query = baseQuery(for: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    switch status {
    case errSecSuccess:
      return result as? Data
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainError.unexpectedStatus(status)
    }
  }

  nonisolated func set(_ data: Data, for account: String, accessible: CFString? = nil) throws {
    let accessibility = accessible ?? defaultAccessibility
    let query = baseQuery(for: account)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: accessibility,
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

    switch updateStatus {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var addQuery = query
      addQuery.merge(attributes) { _, new in new }
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw KeychainError.unexpectedStatus(addStatus)
      }
    default:
      throw KeychainError.unexpectedStatus(updateStatus)
    }
  }

  nonisolated func removeValue(for account: String) throws {
    let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }

  private nonisolated func baseQuery(for account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

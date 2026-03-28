import Darwin
import Foundation
import os
import Security
import UIKit

struct SecurityRuntimeState: Codable, Equatable, Sendable {
  let isDebuggerAttached: Bool
  let isJailbroken: Bool
  let deviceFingerprint: String
  let evaluatedAt: Date

  /// Only jailbroken devices are considered suspicious for rate limiting.
  /// Debugger attachment (Xcode) is excluded — it only affects developers during testing
  /// and was causing unnecessary 3x rate limit penalties.
  nonisolated var isSuspiciousEnvironment: Bool {
    isJailbroken
  }
}

struct SecurityEvent: Codable, Equatable, Sendable {
  enum Kind: String, Codable, Sendable {
    case debuggerDetected
    case jailbreakDetected
    case keyMigrationFailed
    case keychainFailure
    case requestBurstRejected
    case deviceFingerprintChanged
  }

  let kind: Kind
  let timestamp: Date
  let detail: String?
}

final class SecurityManager: @unchecked Sendable {
  static let shared = SecurityManager()

  private enum StorageKey {
    static let installationID = "security.installation.id"
    static let events = "security.events"
  }

  private let secureStore: SecureValueStore
  private let lock = NSLock()
  private var cachedRuntimeState: SecurityRuntimeState?
  private let vendorID: String

  init(secureStore: SecureValueStore? = nil) {
    self.secureStore = secureStore ?? KeychainService.shared
    // Cache vendor ID at init (runs on main thread via static let shared)
    self.vendorID = UIDevice.current.identifierForVendor?.uuidString ?? "vendor-unavailable"
  }

  func prepareForLaunch() {
    _ = persistentInstallationID()
    _ = currentRuntimeState(forceRefresh: true)
  }

  func currentRuntimeState(forceRefresh: Bool = false) -> SecurityRuntimeState {
    lock.lock()
    if let cachedRuntimeState, !forceRefresh {
      lock.unlock()
      return cachedRuntimeState
    }
    lock.unlock()

    let state = SecurityRuntimeState(
      isDebuggerAttached: detectDebugger(),
      isJailbroken: detectJailbreak(),
      deviceFingerprint: deviceFingerprint(),
      evaluatedAt: Date()
    )

    lock.lock()
    let previousState = cachedRuntimeState
    cachedRuntimeState = state
    lock.unlock()

    if previousState?.isDebuggerAttached != true && state.isDebuggerAttached {
      recordEvent(.debuggerDetected, detail: "Debugger attached during runtime assessment.")
    }

    if previousState?.isJailbroken != true && state.isJailbroken {
      recordEvent(.jailbreakDetected, detail: "Jailbreak indicators matched local heuristics.")
    }

    return state
  }

  func deviceFingerprint() -> String {
    "\(vendorID):\(persistentInstallationID())"
  }

  func persistentInstallationID() -> String {
    lock.lock()
    defer { lock.unlock() }

    if let existing = try? secureStore.string(for: StorageKey.installationID), !existing.isEmpty {
      return existing
    }

    let identifier = UUID().uuidString

    do {
      try secureStore.set(
        identifier,
        for: StorageKey.installationID,
        accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      )
    } catch {
      recordEvent(.keychainFailure, detail: "Failed to persist installation ID: \(error)")
    }

    return identifier
  }

  private static let maxEventCount = 25
  private var cachedEvents: [SecurityEvent]?

  func recordEvent(_ kind: SecurityEvent.Kind, detail: String? = nil) {
    let updatedEvents: [SecurityEvent]

    lock.lock()
    var events = cachedEvents
      ?? (try? secureStore.codable([SecurityEvent].self, for: StorageKey.events))
      ?? []
    events.append(SecurityEvent(kind: kind, timestamp: Date(), detail: detail))
    if events.count > Self.maxEventCount {
      events.removeFirst(events.count - Self.maxEventCount)
    }
    cachedEvents = events
    updatedEvents = events
    lock.unlock()

    // Keychain write outside the lock to avoid contention
    do {
      try secureStore.setCodable(
        updatedEvents,
        for: StorageKey.events,
        accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      )
    } catch {
      AppLogger.app.error("Security event persistence failed: \(error)")
    }
  }

  func recentEvents() -> [SecurityEvent] {
    lock.lock()
    let events = cachedEvents
    lock.unlock()
    return events
      ?? (try? secureStore.codable([SecurityEvent].self, for: StorageKey.events))
      ?? []
  }

  private func detectDebugger() -> Bool {
    guard !isRunningTests else { return false }
    #if targetEnvironment(simulator)
      return false
    #else
      var info = kinfo_proc()
      var size = MemoryLayout<kinfo_proc>.stride
      var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
      let status = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
      guard status == 0 else { return false }
      return (info.kp_proc.p_flag & P_TRACED) != 0
    #endif
  }

  private func detectJailbreak() -> Bool {
    guard !isRunningTests else { return false }
    #if targetEnvironment(simulator)
      return false
    #else
      let suspiciousPaths = [
        "/Applications/Cydia.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt/",
      ]

      if suspiciousPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
        return true
      }

      // Check if we can write outside the sandbox (non-destructive, leaves no files)
      if access("/private/", W_OK) == 0 {
        return true
      }

      return false
    #endif
  }

  private var isRunningTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }
}

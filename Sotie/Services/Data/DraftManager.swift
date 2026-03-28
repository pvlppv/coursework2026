import Foundation
import os

/// Manages draft text (just the observation field) that persists across app sessions
final class DraftManager {
  static let shared = DraftManager()

  private let userDefaults = UserDefaults.standard
  private let addEntryDraftKey = "\(DeveloperConfig.appBundleID).addEntryDraft"
  private let editEntryDraftPrefix = "\(DeveloperConfig.appBundleID).editEntryDraft."

  private init() {}

  // MARK: - Add Entry Draft (just the observation text field)

  func saveAddEntryDraft(observation: String) {
    userDefaults.set(observation, forKey: addEntryDraftKey)
    AppLogger.data.debug("Saved AddEntry draft text")
  }

  func loadAddEntryDraft() -> String? {
    let text = userDefaults.string(forKey: addEntryDraftKey)
    if text != nil {
      AppLogger.data.debug("Loaded AddEntry draft text")
    }
    return text
  }

  func clearAddEntryDraft() {
    userDefaults.removeObject(forKey: addEntryDraftKey)
    AppLogger.data.debug("Cleared AddEntry draft")
  }

  // MARK: - Add Entry Prompt Seed Draft

  /// Persists the prompt seed picked in the empty state so it survives a
  /// kill/restart of the app while the entry is unsaved.
  ///
  /// v2 schema (cluster-aware):
  ///   { "v": 2, "clusterId": "heavy", "subStateId": "numb",
  ///     "openerText": "…", "openerIndex": 3 }
  ///
  /// v1 schema (legacy, single category):
  ///   { "categoryId": "heavy", "openerText": "…", "openerIndex": 3 }
  ///
  /// `loadPromptDraft()` migrates v1 drafts in-memory; v1 drafts whose
  /// category mapped to the now-removed Continue/Returning clusters are
  /// dropped silently.
  private var addEntryPromptDraftKey: String {
    "\(DeveloperConfig.appBundleID).addEntryPromptDraft"
  }

  func savePromptDraft(
    clusterId: String,
    subStateId: String,
    openerText: String,
    openerIndex: Int
  ) {
    let payload: [String: Any] = [
      "v": 2,
      "clusterId": clusterId,
      "subStateId": subStateId,
      "openerText": openerText,
      "openerIndex": openerIndex,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload),
      let json = String(data: data, encoding: .utf8)
    {
      userDefaults.set(json, forKey: addEntryPromptDraftKey)
      AppLogger.data.debug("Saved AddEntry prompt draft for cluster=\(clusterId) subState=\(subStateId)")
    }
  }

  func loadPromptDraft() -> (
    clusterId: String, subStateId: String, openerText: String, openerIndex: Int
  )? {
    guard let json = userDefaults.string(forKey: addEntryPromptDraftKey),
      let data = json.data(using: .utf8),
      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let openerText = payload["openerText"] as? String,
      let openerIndex = payload["openerIndex"] as? Int
    else {
      return nil
    }

    // v2 — read cluster + sub-state directly.
    if let version = payload["v"] as? Int, version == 2,
      let clusterId = payload["clusterId"] as? String,
      let subStateId = payload["subStateId"] as? String
    {
      return (clusterId, subStateId, openerText, openerIndex)
    }

    // v1 migration — map legacy categoryId → cluster + sub-state.
    if let categoryId = payload["categoryId"] as? String {
      switch categoryId {
      case "morning", "evening", "late_night":
        return ("time", categoryId, openerText, openerIndex)
      case "stuck", "replay", "restless":
        return ("looping", categoryId, openerText, openerIndex)
      case "heavy", "numb", "anxious", "frustrated":
        return ("heavy", categoryId, openerText, openerIndex)
      case "someone", "you_vs_them":
        return ("someone", categoryId, openerText, openerIndex)
      case "decision", "change":
        return ("choosing", categoryId, openerText, openerIndex)
      case "wins", "gratitude", "patterns", "future_self":
        return ("notice", categoryId, openerText, openerIndex)
      case "brain_dump":
        return ("brain_dump", categoryId, openerText, openerIndex)
      case "continue", "returning":
        // Continue/Returning clusters were removed because each entry's
        // AI conversation has no cross-entry memory. Drop the draft.
        clearPromptDraft()
        return nil
      default:
        return nil
      }
    }

    return nil
  }

  func clearPromptDraft() {
    userDefaults.removeObject(forKey: addEntryPromptDraftKey)
    AppLogger.data.debug("Cleared AddEntry prompt draft")
  }

  // MARK: - Edit Entry Draft (just the observation text field)

  func saveEditEntryDraft(entryId: String, observation: String) {
    let key = editEntryDraftPrefix + entryId
    userDefaults.set(observation, forKey: key)
    AppLogger.data.debug("Saved EditEntry draft text for \(entryId)")
  }

  func loadEditEntryDraft(entryId: String) -> String? {
    let key = editEntryDraftPrefix + entryId
    let text = userDefaults.string(forKey: key)
    if text != nil {
      AppLogger.data.debug("Loaded EditEntry draft text for \(entryId)")
    }
    return text
  }

  func clearEditEntryDraft(entryId: String) {
    let key = editEntryDraftPrefix + entryId
    userDefaults.removeObject(forKey: key)
    AppLogger.data.debug("Cleared EditEntry draft for \(entryId)")
  }

  // MARK: - Cleanup

  /// Clears all edit entry drafts (useful for cleanup)
  func clearAllEditEntryDrafts() {
    let allKeys = userDefaults.dictionaryRepresentation().keys
    let draftKeys = allKeys.filter { $0.hasPrefix(editEntryDraftPrefix) }

    for key in draftKeys {
      userDefaults.removeObject(forKey: key)
    }

    AppLogger.data.debug("Cleared all EditEntry drafts (\(draftKeys.count) drafts)")
  }
}

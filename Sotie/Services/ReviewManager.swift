//
//  ReviewManager.swift
//  Sotie
//
//  Intelligent App Store review prompt manager.
//  Triggers review request after confirmed value (2nd AI-assisted save),
//  respecting friction, cooldown, and premium gating.
//
//

import Foundation
import os
import StoreKit
import UIKit

/// Manages App Store review prompt timing based on user behavior signals.
///
/// Gating conditions (ALL must be true):
/// 1. User saved ≥2 AI-assisted entries
/// 2. User was active on ≥2 distinct calendar dates
/// 3. User is premium or trial
/// 4. No friction in current session (paywall, notification permission, error)
/// 5. Last review prompt was >120 days ago (or never shown)
@MainActor
final class ReviewManager {
  static let shared = ReviewManager()

  // MARK: - UserDefaults Keys

  private let aiSaveCountKey = "ReviewManager.aiAssistedSaveCount"
  private let activeDatesKey = "ReviewManager.activeDates"
  private let lastPromptDateKey = "ReviewManager.lastReviewPromptDate"

  // MARK: - Constants

  /// Minimum AI-assisted saves before requesting review
  private let requiredAISaves = 2

  /// Minimum distinct active dates before requesting review
  private let requiredActiveDates = 2

  /// Cooldown between review prompts (120 days)
  private let cooldownInterval: TimeInterval = 120 * 24 * 60 * 60

  // MARK: - Session State (in-memory, resets per app session)

  /// Set to `true` when paywall, notification permission, or error occurs in this session.
  /// Prevents review prompt from appearing in a session with friction.
  private(set) var sessionHadFriction = false

  /// Tracks whether a review prompt was already triggered in this session.
  private var promptShownThisSession = false

  private init() {}

  // MARK: - Recording

  /// Call after saving an entry that has AI conversation.
  func recordAIAssistedSave() {
    let defaults = UserDefaults.standard

    // Increment AI save count
    let currentCount = defaults.integer(forKey: aiSaveCountKey)
    defaults.set(currentCount + 1, forKey: aiSaveCountKey)

    // Add today's date to active dates set
    let today = Self.todayString()
    var dates = loadActiveDates()
    dates.insert(today)
    saveActiveDates(dates)

    AppLogger.app.info("ReviewManager: AI save #\(currentCount + 1), active dates: \(dates.count)")
  }

  /// Call when a friction event occurs (paywall shown, notification permission asked, error).
  func recordSessionFriction() {
    sessionHadFriction = true
    AppLogger.app.info("ReviewManager: Session friction recorded")
  }

  /// Call on app launch / return to foreground to reset session friction.
  func resetSessionFriction() {
    sessionHadFriction = false
  }

  // MARK: - Gating

  /// Checks all gating conditions for showing review prompt.
  func shouldRequestReview() -> Bool {
    // Already shown this session
    guard !promptShownThisSession else {
      AppLogger.app.info("ReviewManager: Skip — already shown this session")
      return false
    }

    let defaults = UserDefaults.standard

    // 1. Enough AI-assisted saves
    let saveCount = defaults.integer(forKey: aiSaveCountKey)
    guard saveCount >= requiredAISaves else {
      AppLogger.app.info("ReviewManager: Skip — AI saves \(saveCount)/\(self.requiredAISaves)")
      return false
    }

    // 2. Active on enough distinct dates
    let activeDates = loadActiveDates()
    guard activeDates.count >= requiredActiveDates else {
      AppLogger.app.info("ReviewManager: Skip — active dates \(activeDates.count)/\(self.requiredActiveDates)")
      return false
    }

    // 3. Premium or trial
    guard PremiumManager.shared.subscriptionStatus.isPremium else {
      AppLogger.app.info("ReviewManager: Skip — not premium")
      return false
    }

    // 4. No friction this session
    guard !sessionHadFriction else {
      AppLogger.app.info("ReviewManager: Skip — session had friction")
      return false
    }

    // 5. Cooldown (120 days since last prompt)
    if let lastPrompt = defaults.object(forKey: lastPromptDateKey) as? Date {
      let elapsed = Date().timeIntervalSince(lastPrompt)
      guard elapsed >= cooldownInterval else {
        AppLogger.app.info("ReviewManager: Skip — cooldown (\(Int(elapsed / 86400))d / \(Int(self.cooldownInterval / 86400))d)")
        return false
      }
    }

    return true
  }

  /// Checks eligibility and requests App Store review if all conditions are met.
  /// Call after user returns to home screen from an entry editor.
  func requestReviewIfEligible() {
    guard shouldRequestReview() else { return }

    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
      AppLogger.app.warning("ReviewManager: No window scene available")
      return
    }

    AppLogger.app.info("ReviewManager: Requesting App Store review")

    // Mark as shown
    promptShownThisSession = true
    UserDefaults.standard.set(Date(), forKey: lastPromptDateKey)

    // Track in analytics
    Analytics.reviewPromptShown()

    // Use the system review prompt (Apple decides whether to actually show it)
    if #available(iOS 18.0, *) {
      AppStore.requestReview(in: windowScene)
    } else {
      SKStoreReviewController.requestReview(in: windowScene)
    }
  }

  /// Forces a review prompt at a celebratory moment (e.g. end of onboarding).
  /// Bypasses the gating used by `requestReviewIfEligible` (premium / save count /
  /// active dates) because the user hasn't earned those signals yet, but still:
  ///   - respects the 120-day cooldown so we don't burn an iOS prompt slot
  ///   - records the timestamp so the home-screen path won't double-fire
  ///   - marks the session as shown to avoid re-prompting in the same session
  func requestReviewForCelebration() {
    guard !promptShownThisSession else {
      AppLogger.app.info("ReviewManager: Skip celebration — already shown this session")
      return
    }

    if let lastPrompt = UserDefaults.standard.object(forKey: lastPromptDateKey) as? Date {
      let elapsed = Date().timeIntervalSince(lastPrompt)
      guard elapsed >= cooldownInterval else {
        AppLogger.app.info("ReviewManager: Skip celebration — cooldown (\(Int(elapsed / 86400))d / \(Int(self.cooldownInterval / 86400))d)")
        return
      }
    }

    guard let windowScene = UIApplication.shared
      .connectedScenes
      .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
      ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
    else {
      AppLogger.app.warning("ReviewManager: No window scene available for celebration prompt")
      return
    }

    AppLogger.app.info("ReviewManager: Requesting App Store review (celebration)")

    promptShownThisSession = true
    UserDefaults.standard.set(Date(), forKey: lastPromptDateKey)
    Analytics.reviewPromptShown()

    if #available(iOS 18.0, *) {
      AppStore.requestReview(in: windowScene)
    } else {
      SKStoreReviewController.requestReview(in: windowScene)
    }
  }

  // MARK: - Active Dates Persistence

  private func loadActiveDates() -> Set<String> {
    let array = UserDefaults.standard.stringArray(forKey: activeDatesKey) ?? []
    return Set(array)
  }

  private func saveActiveDates(_ dates: Set<String>) {
    UserDefaults.standard.set(Array(dates), forKey: activeDatesKey)
  }

  private static func todayString() -> String {
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month, .day], from: Date())
    return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
  }
}

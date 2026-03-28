//
//  Analytics.swift
//  Sotie
//
//  Privacy-first analytics via TelemetryDeck.
//  No PII collected. No consent banner required.
//  Signals are anonymous & aggregated on TelemetryDeck's servers.
//
//

import Foundation
import os
import TelemetryDeck

// MARK: - Analytics Service

/// Centralized analytics wrapper around TelemetryDeck.
/// All event names and parameters are defined here to keep tracking consistent.
enum Analytics {

  enum GoDeeperTrigger: String {
    case start
    case `continue` = "continue"
    case editRegenerate = "edit_regenerate"
    case refreshLastAssistant = "refresh_last_assistant"
    case retry
  }

  enum GoDeeperStage: String {
    case quotaCheck = "quota_check"
    case validation
    case generation
    case postprocess
  }

  enum GoDeeperSaveAction: String {
    case saved
    case unsaved
  }

  // MARK: - Configuration

  /// Initialize TelemetryDeck. Call once in AppDelegate.didFinishLaunching.
  static func configure() {
    let config = TelemetryDeck.Config(appID: "5C35B0B5-44AC-4E21-94B2-CF0FBB49A689")

    // TelemetryDeck hashes user identifiers by default — no raw IDs leave the device.
    // testMode sends signals to a separate test pipeline (only in DEBUG).
    #if DEBUG
      config.testMode = true
    #endif

    TelemetryDeck.initialize(config: config)
    AppLogger.app.info("TelemetryDeck initialized")
  }

  // MARK: - App Lifecycle

  /// App launched (cold start)
  static func appLaunched() {
    TelemetryDeck.signal("App.launched")
  }

  /// App returned from background
  static func appResumed() {
    TelemetryDeck.signal("App.resumed")
  }

  /// App Store review prompt was triggered
  static func reviewPromptShown() {
    TelemetryDeck.signal("App.reviewPromptShown")
  }

  // MARK: - Onboarding

  /// User completed onboarding
  static func onboardingCompleted() {
    TelemetryDeck.signal("Onboarding.completed")
  }

  /// A new onboarding step was rendered. Fired once per step view.
  /// `index` is the step's raw value (0-32) so server-side ordering is trivial.
  static func onboardingStepViewed(step: String, index: Int) {
    TelemetryDeck.signal(
      "Onboarding.stepViewed",
      parameters: [
        "step": step,
        "stepIndex": "\(index)",
      ]
    )
  }

  /// User advanced to the next onboarding step (forward navigation).
  static func onboardingStepAdvanced(from: String, to: String) {
    TelemetryDeck.signal(
      "Onboarding.stepAdvanced",
      parameters: [
        "from": from,
        "to": to,
      ]
    )
  }

  /// User went back to the previous onboarding step.
  static func onboardingStepBacked(from: String, to: String) {
    TelemetryDeck.signal(
      "Onboarding.stepBacked",
      parameters: [
        "from": from,
        "to": to,
      ]
    )
  }

  /// Logs each survey selection. `question` is the survey screen identifier
  /// (e.g. "thoughtType", "vision", "commitment"); `answer` is the enum
  /// rawValue so language-localized titles don't pollute the data.
  /// For multi-select (goals), pass a comma-joined sorted list.
  static func onboardingSurveyAnswered(question: String, answer: String) {
    TelemetryDeck.signal(
      "Onboarding.surveyAnswered",
      parameters: [
        "question": question,
        "answer": answer,
      ]
    )
  }

  /// User picked a language from the onboarding language switcher.
  /// Distinct from Settings.languageChanged so the funnel can show drop-offs
  /// related to wrong-language detection.
  static func onboardingLanguageSelected(code: String) {
    TelemetryDeck.signal(
      "Onboarding.languageSelected",
      parameters: [
        "language": code,
      ]
    )
  }

  /// User responded to the notifications priming alert.
  static func onboardingNotificationDecision(allowed: Bool) {
    TelemetryDeck.signal(
      "Onboarding.notificationDecision",
      parameters: [
        "allowed": "\(allowed)",
      ]
    )
  }

  /// User finished the onboarding demo conversation (or left it).
  static func onboardingDemoFinished(messageCount: Int, durationSeconds: Double) {
    TelemetryDeck.signal(
      "Onboarding.demoFinished",
      parameters: [
        "messageCountBucket": conversationDepthBucket(for: messageCount),
        "durationBucket": durationBucket(for: durationSeconds),
      ]
    )
  }

  /// User abandoned onboarding mid-flow (app killed or scene disconnected).
  /// Fired from scene-disconnect handler with the last visited step.
  static func onboardingAbandoned(lastStep: String, lastStepIndex: Int) {
    TelemetryDeck.signal(
      "Onboarding.abandoned",
      parameters: [
        "lastStep": lastStep,
        "lastStepIndex": "\(lastStepIndex)",
      ]
    )
  }

  private static func durationBucket(for seconds: Double) -> String {
    switch seconds {
    case ..<10: return "0-9"
    case 10..<30: return "10-29"
    case 30..<60: return "30-59"
    case 60..<180: return "60-179"
    default: return "180+"
    }
  }

  // MARK: - Legacy: Onboarding Checkpoint & Resume Nudge
  //
  // The "checkpoint card" used to appear inline after the free AI rounds
  // were exhausted in the demo, and the resume-nudge campaign sent push
  // reminders to users who skipped the paywall. Hard-paywall onboarding
  // now routes everyone through `.onboardingPaywall`, so neither of these
  // signal sources fire today. Symbols are kept defined so any pending
  // analytics consumers don't break; remove once we're confident nothing
  // depends on them.

  /// Checkpoint card shown after free AI rounds exhausted
  @available(*, deprecated, message: "Legacy checkpoint flow removed; replaced by hard-paywall onboarding step.")
  static func onboardingCheckpointShown(roundsCompleted: Int) {
    TelemetryDeck.signal(
      "Onboarding.checkpointShown",
      parameters: [
        "roundsCompleted": "\(roundsCompleted)",
      ]
    )
  }

  /// User tapped "Continue This Conversation" on checkpoint card
  @available(*, deprecated, message: "Legacy checkpoint flow removed; replaced by hard-paywall onboarding step.")
  static func onboardingCheckpointCTATapped() {
    TelemetryDeck.signal("Onboarding.checkpointCTATapped")
  }

  /// Onboarding resume nudge campaign scheduled
  @available(*, deprecated, message: "Legacy resume nudge campaign no longer scheduled. Cancel paths kept defensively.")
  static func onboardingResumeScheduled(steps: Int) {
    TelemetryDeck.signal(
      "OnboardingResume.scheduled",
      parameters: [
        "steps": "\(steps)",
      ]
    )
  }

  /// Onboarding resume nudge campaign cancelled
  static func onboardingResumeCancelled(reason: String) {
    TelemetryDeck.signal(
      "OnboardingResume.cancelled",
      parameters: [
        "reason": reason,
      ]
    )
  }

  // MARK: - Entry Lifecycle

  /// User created a new journal entry
  static func entryCreated(wordCount: Int, hasAIConversation: Bool) {
    TelemetryDeck.signal(
      "Entry.created",
      parameters: [
        "wordCountBucket": bucket(for: wordCount),
        "hasAIConversation": "\(hasAIConversation)",
      ]
    )
  }

  /// User opened an existing entry for editing
  static func entryOpened() {
    TelemetryDeck.signal("Entry.opened")
  }

  /// User deleted an entry
  static func entryDeleted() {
    TelemetryDeck.signal("Entry.deleted")
  }

  // MARK: - AI Conversation (Core Feature)

  /// User tapped "Go Deeper" to start/continue AI conversation
  static func goDeeper(responseNumber: Int) {
    TelemetryDeck.signal(
      "AI.goDeeper",
      parameters: [
        "responseNumber": "\(min(responseNumber, 20))",
      ]
    )
  }

  static func goDeeperRequested(
    responseNumber: Int,
    trigger: GoDeeperTrigger,
    hasSummary: Bool,
    conversationDepth: Int,
    isFirstAssistantMessage: Bool
  ) {
    TelemetryDeck.signal(
      "AI.goDeeperRequested",
      parameters: goDeeperRequestedParameters(
        responseNumber: responseNumber,
        trigger: trigger,
        hasSummary: hasSummary,
        conversationDepth: conversationDepth,
        isFirstAssistantMessage: isFirstAssistantMessage
      )
    )
  }

  static func goDeeperCompleted(
    responseNumber: Int,
    trigger: GoDeeperTrigger,
    latencyMs: Int?,
    responseLength: Int,
    hasSummary: Bool,
    isFirstAssistantMessage: Bool
  ) {
    TelemetryDeck.signal(
      "AI.goDeeperCompleted",
      parameters: goDeeperCompletedParameters(
        responseNumber: responseNumber,
        trigger: trigger,
        latencyMs: latencyMs,
        responseLength: responseLength,
        hasSummary: hasSummary,
        isFirstAssistantMessage: isFirstAssistantMessage
      )
    )
  }

  static func goDeeperCancelled(
    responseNumber: Int,
    trigger: GoDeeperTrigger,
    hadPlaceholderAssistant: Bool,
    wasInPlaceRegeneration: Bool
  ) {
    TelemetryDeck.signal(
      "AI.goDeeperCancelled",
      parameters: goDeeperCancelledParameters(
        responseNumber: responseNumber,
        trigger: trigger,
        hadPlaceholderAssistant: hadPlaceholderAssistant,
        wasInPlaceRegeneration: wasInPlaceRegeneration
      )
    )
  }

  /// AI request failed
  static func aiError(reason: String) {
    TelemetryDeck.signal(
      "AI.error",
      parameters: [
        "reason": reason,
      ]
    )
  }

  static func aiError(
    reason: String,
    stage: GoDeeperStage,
    trigger: GoDeeperTrigger,
    responseNumber: Int,
    isRetryable: Bool
  ) {
    TelemetryDeck.signal(
      "AI.error",
      parameters: goDeeperErrorParameters(
        reason: reason,
        stage: stage,
        trigger: trigger,
        responseNumber: responseNumber,
        isRetryable: isRetryable
      )
    )
  }

  /// User saved an AI-generated response to their collection
  static func questionSaved() {
    TelemetryDeck.signal("AI.questionSaved")
  }

  static func goDeeperUseful(
    responseNumber: Int,
    saveAction: GoDeeperSaveAction,
    latencyMs: Int?,
    isLastMessage: Bool
  ) {
    TelemetryDeck.signal(
      "AI.goDeeperUseful",
      parameters: goDeeperUsefulParameters(
        responseNumber: responseNumber,
        saveAction: saveAction,
        latencyMs: latencyMs,
        isLastMessage: isLastMessage
      )
    )
  }

  static func languageChanged(to language: String) {
    TelemetryDeck.signal(
      "Settings.languageChanged",
      parameters: [
        "language": language,
      ]
    )
  }

  static func themeChanged(to variant: String) {
    TelemetryDeck.signal(
      "Settings.themeChanged",
      parameters: [
        "variant": variant,
      ]
    )
  }

  // MARK: - Prompt Cards

  /// User tapped a cluster card on the rail and an opener was seeded.
  static func promptCardTapped(
    cluster: String,
    subState: String,
    openerIndex: Int,
    hour: Int
  ) {
    TelemetryDeck.signal(
      "Prompt.cardTapped",
      parameters: [
        "cluster": cluster,
        "subState": subState,
        "openerIndex": String(openerIndex),
        "hour": String(hour),
      ]
    )
  }

  /// User tapped an already-selected cluster to deselect it.
  static func promptCardDeselected(cluster: String) {
    TelemetryDeck.signal(
      "Prompt.cardDeselected",
      parameters: [
        "cluster": cluster,
      ]
    )
  }

  /// Entry was saved with a prompt seed. Tracks whether the user actually
  /// replied to the opener (vs saving an empty entry with just the seed).
  static func promptSeedCommitted(
    cluster: String,
    subState: String,
    openerIndex: Int,
    userReplied: Bool
  ) {
    TelemetryDeck.signal(
      "Prompt.seedCommitted",
      parameters: [
        "cluster": cluster,
        "subState": subState,
        "openerIndex": String(openerIndex),
        "userReplied": String(userReplied),
      ]
    )
  }

  /// Fired once per AddEntry open. Records which clusters were shown and
  /// in what order so we can measure rail composition vs engagement.
  static func promptRailImpression(clusters: [String]) {
    TelemetryDeck.signal(
      "Prompt.railImpression",
      parameters: [
        "clusters": clusters.joined(separator: ","),
        "count": String(clusters.count),
      ]
    )
  }

  private static func signal(_ name: String, paywallContext: PaywallAnalyticsContext) {
    TelemetryDeck.signal(name, parameters: paywallContext.parameters)
  }

  private static func signal(
    _ name: String,
    paywallContext: PaywallAnalyticsContext,
    extraParameters: [String: String]
  ) {
    TelemetryDeck.signal(
      name,
      parameters: paywallContext.parameters.merging(extraParameters) { _, new in new }
    )
  }

  // MARK: - Subscription Funnel

  /// Paywall was shown to the user
  static func paywallViewed(context: PaywallAnalyticsContext) {
    signal("Subscription.paywallViewed", paywallContext: context)

    // Paywall is a friction event — suppress review prompt this session
    ReviewManager.shared.recordSessionFriction()
  }

  /// User selected a product on the paywall
  static func productSelected(context: PaywallAnalyticsContext) {
    signal("Subscription.productSelected", paywallContext: context)
  }

  /// User initiated a purchase
  static func purchaseStarted(context: PaywallAnalyticsContext) {
    signal("Subscription.purchaseStarted", paywallContext: context)
  }

  /// Purchase completed successfully
  static func purchaseCompleted(context: PaywallAnalyticsContext) {
    signal("Subscription.purchaseCompleted", paywallContext: context)
  }

  /// User cancelled purchase flow
  static func purchaseCancelled(context: PaywallAnalyticsContext) {
    signal("Subscription.purchaseCancelled", paywallContext: context)
  }

  /// User dismissed the paywall without purchasing
  static func paywallDismissed(context: PaywallAnalyticsContext) {
    signal("Subscription.paywallDismissed", paywallContext: context)
  }

  /// Free user tapped FAB (+) and was blocked
  static func freeFABBlocked() {
    TelemetryDeck.signal("Subscription.freeFABBlocked")
  }

  /// Free user attempted AI and was blocked
  static func freeAIBlocked() {
    TelemetryDeck.signal("Subscription.freeAIBlocked")
  }

  /// Trial started (user subscribed with intro offer)
  static func trialStarted(productId: String, context: PaywallAnalyticsContext? = nil) {
    if let context {
      signal(
        "Subscription.trialStarted",
        paywallContext: context,
        extraParameters: ["productId": productId]
      )
      return
    }

    TelemetryDeck.signal(
      "Subscription.trialStarted",
      parameters: [
        "productId": productId,
      ]
    )
  }

  /// Trial converted to paid (renewal after trial)
  static func trialConverted(productId: String, context: PaywallAnalyticsContext? = nil) {
    if let context {
      signal(
        "Subscription.trialConverted",
        paywallContext: context,
        extraParameters: ["productId": productId]
      )
      return
    }

    TelemetryDeck.signal(
      "Subscription.trialConverted",
      parameters: [
        "productId": productId,
      ]
    )
  }

  /// Subscription expired (churn)
  static func subscriptionExpired(productId: String, context: PaywallAnalyticsContext? = nil) {
    if let context {
      signal(
        "Subscription.expired",
        paywallContext: context,
        extraParameters: ["productId": productId]
      )
      return
    }

    TelemetryDeck.signal(
      "Subscription.expired",
      parameters: [
        "productId": productId,
      ]
    )
  }

  // MARK: - Notifications

  /// User tapped a notification to open the app
  static func notificationTapped(type: String) {
    TelemetryDeck.signal(
      "Notification.tapped",
      parameters: [
        "notificationType": type,
      ]
    )
  }

  // MARK: - Navigation (built-in TelemetryDeck feature)

  /// Track screen navigation for funnel analysis
  static func screenViewed(_ screenName: String) {
    TelemetryDeck.navigationPathChanged(to: screenName)
  }

  // MARK: - Data Management

  /// User exported their journal data
  static func dataExported() {
    TelemetryDeck.signal("Data.exported")
  }

  /// User imported journal data
  static func dataImported(entryCount: Int) {
    TelemetryDeck.signal(
      "Data.imported",
      parameters: [
        "entryCountBucket": bucket(for: entryCount),
      ]
    )
  }

  // MARK: - Feature Usage

  /// User toggled daily reminder
  static func dailyReminderToggled(enabled: Bool) {
    TelemetryDeck.signal(
      "Settings.dailyReminder",
      parameters: [
        "enabled": "\(enabled)",
      ]
    )
  }

  // MARK: - Helpers

  /// Bucket word counts to avoid high-cardinality (privacy + performance)
  private static func bucket(for count: Int) -> String {
    switch count {
    case 0: return "0"
    case 1...10: return "1-10"
    case 11...50: return "11-50"
    case 51...100: return "51-100"
    case 101...250: return "101-250"
    case 251...500: return "251-500"
    default: return "500+"
    }
  }

  static func goDeeperRequestedParameters(
    responseNumber: Int,
    trigger: GoDeeperTrigger,
    hasSummary: Bool,
    conversationDepth: Int,
    isFirstAssistantMessage: Bool
  ) -> [String: String] {
    [
      "responseNumber": "\(min(max(responseNumber, 1), 20))",
      "trigger": trigger.rawValue,
      "deliveryMode": "streaming",
      "hasSummary": "\(hasSummary)",
      "conversationDepthBucket": conversationDepthBucket(for: conversationDepth),
      "isFirstAssistantMessage": "\(isFirstAssistantMessage)",
    ]
  }

  static func goDeeperCompletedParameters(
    responseNumber: Int,
    trigger: GoDeeperTrigger,
    latencyMs: Int?,
    responseLength: Int,
    hasSummary: Bool,
    isFirstAssistantMessage: Bool
  ) -> [String: String] {
    var parameters = [
      "responseNumber": "\(min(max(responseNumber, 1), 20))",
      "trigger": trigger.rawValue,
      "deliveryMode": "streaming",
      "responseLengthBucket": responseLengthBucket(for: responseLength),
      "hasSummary": "\(hasSummary)",
      "isFirstAssistantMessage": "\(isFirstAssistantMessage)",
    ]

    if let latencyMs {
      parameters["latencyMs"] = "\(latencyMs)"
      parameters["latencyBucket"] = latencyBucket(for: latencyMs)
    } else {
      parameters["latencyBucket"] = "unknown"
    }

    return parameters
  }

  static func goDeeperCancelledParameters(
    responseNumber: Int,
    trigger: GoDeeperTrigger,
    hadPlaceholderAssistant: Bool,
    wasInPlaceRegeneration: Bool
  ) -> [String: String] {
    [
      "responseNumber": "\(min(max(responseNumber, 1), 20))",
      "trigger": trigger.rawValue,
      "deliveryMode": "streaming",
      "phase": "in_flight",
      "hadPlaceholderAssistant": "\(hadPlaceholderAssistant)",
      "wasInPlaceRegeneration": "\(wasInPlaceRegeneration)",
    ]
  }

  static func goDeeperErrorParameters(
    reason: String,
    stage: GoDeeperStage,
    trigger: GoDeeperTrigger,
    responseNumber: Int,
    isRetryable: Bool
  ) -> [String: String] {
    [
      "reason": reason,
      "stage": stage.rawValue,
      "trigger": trigger.rawValue,
      "deliveryMode": "streaming",
      "responseNumber": "\(min(max(responseNumber, 1), 20))",
      "isRetryable": "\(isRetryable)",
    ]
  }

  static func goDeeperUsefulParameters(
    responseNumber: Int,
    saveAction: GoDeeperSaveAction,
    latencyMs: Int?,
    isLastMessage: Bool
  ) -> [String: String] {
    var parameters = [
      "responseNumber": "\(min(max(responseNumber, 1), 20))",
      "saveAction": saveAction.rawValue,
      "isLastMessage": "\(isLastMessage)",
    ]

    if let latencyMs {
      parameters["latencyBucket"] = latencyBucket(for: latencyMs)
    } else {
      parameters["latencyBucket"] = "unknown"
    }
    return parameters
  }

  static func latencyBucket(for latencyMs: Int) -> String {
    switch latencyMs {
    case ..<1000: return "0-999"
    case 1000..<2000: return "1000-1999"
    case 2000..<5000: return "2000-4999"
    default: return "5000+"
    }
  }

  static func responseLengthBucket(for responseLength: Int) -> String {
    switch responseLength {
    case 0..<40: return "0-39"
    case 40..<80: return "40-79"
    case 80..<140: return "80-139"
    default: return "140+"
    }
  }

  static func conversationDepthBucket(for messageCount: Int) -> String {
    switch messageCount {
    case 0...2: return "1-2"
    case 3...4: return "3-4"
    case 5...8: return "5-8"
    default: return "9+"
    }
  }

  // MARK: - Insights

  /// Insights generation started (user tapped Finish with conversation)
  static func insightsRequested(messageCount: Int) {
    TelemetryDeck.signal(
      "Insights.requested",
      parameters: [
        "messageCountBucket": conversationDepthBucket(for: messageCount),
      ]
    )
  }

  /// Insights generated successfully
  static func insightsGenerated(messageCount: Int, latencyMs: Int) {
    TelemetryDeck.signal(
      "Insights.generated",
      parameters: [
        "messageCountBucket": conversationDepthBucket(for: messageCount),
        "latencyBucket": latencyBucket(for: latencyMs),
      ]
    )
  }

  /// Insights generation failed
  static func insightsFailed(reason: String) {
    TelemetryDeck.signal(
      "Insights.failed",
      parameters: [
        "reason": reason,
      ]
    )
  }

  /// User skipped insights (tapped Skip on error)
  static func insightsSkipped() {
    TelemetryDeck.signal("Insights.skipped")
  }

  /// User viewed saved insights from the menu
  static func insightsViewed() {
    TelemetryDeck.signal("Insights.viewed")
  }
}

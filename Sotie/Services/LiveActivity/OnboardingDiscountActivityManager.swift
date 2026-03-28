//
//  OnboardingDiscountActivityManager.swift
//  Sotie
//
//  Owns the lifecycle of the onboarding "limited-time discount"
//  Live Activity. Single-instance squeeze tool: started once when
//  onboarding begins, ended when the user buys, completes onboarding,
//  the timer runs out, or the user becomes premium by any other path
//  (e.g. restore, parental restore).
//
//  Why a `@MainActor`-pinned singleton?
//    - ActivityKit's `Activity.request` / `Activity.update` /
//      `Activity.end` are async and safe off-main, but our caller
//      sites (SwiftUI views) are `@MainActor`. Pinning to MainActor
//      keeps call sites simple and avoids Sendable warnings on the
//      `Activity<…>` reference.
//

import ActivityKit
import Combine
import Foundation
import os

@MainActor
final class OnboardingDiscountActivityManager: ObservableObject {

    static let shared = OnboardingDiscountActivityManager()

    // MARK: - Published state

    /// Date when the current squeeze offer expires. `nil` while inactive.
    /// Bind to this from views to render `Text(timerInterval:countsDown:)`
    /// without a per-second `Timer`.
    @Published private(set) var expiresAt: Date?

    /// `true` while the activity is live (started and not yet ended).
    @Published private(set) var isActive: Bool = false

    /// Convenience: discount percent currently being offered.
    @Published private(set) var discountPercent: Int = 50

    /// Drives sheet presentation from the root `ContentView`. Flipped by:
    ///   - The deep link router (Live Activity tap →
    ///     `sotiejournal://onboarding/discount`).
    ///   - `OnboardingPaywallView` when the user dismisses Apple's
    ///     StoreKit purchase sheet (i.e. tapped a plan, then pulled
    ///     the sheet down).
    /// One source of truth so the root `.sheet` can present the
    /// paywall whether the user is mid-onboarding or already finished.
    @Published var shouldPresentDiscountPaywall: Bool = false

    /// Request that the discount paywall be shown.
    ///
    /// We hop one main-runloop tick before flipping the flag so the
    /// root `.sheet(isPresented:)` binding is fully hydrated when iOS
    /// spawns the app from a Live Activity tap. Without this, cold
    /// launches sometimes schedule a present + immediate dismiss.
    /// One runloop hop (~16ms) is imperceptible, vs. the previous
    /// 350ms which the user could feel as lag.
    func requestPresentation() {
        if let expiresAt, expiresAt <= Date() {
            return  // expired — don't show a stale paywall
        }

        DispatchQueue.main.async { [weak self] in
            self?.shouldPresentDiscountPaywall = true
        }
    }

    // MARK: - Persistence keys

    private enum StorageKey {
        static let expiresAt = "onboardingDiscount.expiresAt"
        static let startedAt = "onboardingDiscount.startedAt"
        static let percent = "onboardingDiscount.percent"
    }

    // MARK: - Internals

    private var activity: Activity<OnboardingDiscountAttributes>?
    private let logger = Logger(subsystem: "com.pvlppv.sotie.journal", category: "OnboardingDiscount")

    /// Tolerance for matching a previously persisted duration against
    /// the current default. Anything older than current default × 2 is
    /// treated as a stale activity from a prior build (e.g. the 24h
    /// version still alive when we shipped 3min) and force-killed.
    private static let staleDurationMultiplier: TimeInterval = 2

    private init() {
        purgeStaleActivitiesIfNeeded()
        restoreFromDefaults()
        rebindExistingActivityIfAny()
    }

    // MARK: - Public API

    /// Start the squeeze. Idempotent: if a real `Activity<…>` handle
    /// is still around AND the timer hasn't expired, we keep it
    /// running. If the OS dropped the activity (force-quit, swipe-
    /// away, system policy) while persisted state still says
    /// "active", we treat that as stale and request a fresh activity.
    /// - Parameter duration: total countdown window. Defaults to 3 minutes.
    func start(duration: TimeInterval = OnboardingDiscountAttributes.defaultDuration,
               percent: Int = 50) {
        if activity != nil, isActive, let expiresAt, expiresAt > Date() {
            logger.debug("Discount activity already running, skipping start.")
            return
        }

        if activity == nil, isActive {
            logger.info("Persisted state present but no live Activity; restarting cleanly.")
            clearPersisted()
            self.isActive = false
            self.expiresAt = nil
        }

        let authorized = ActivityAuthorizationInfo().areActivitiesEnabled

        let now = Date()
        let endsAt = now.addingTimeInterval(duration)
        let attributes = OnboardingDiscountAttributes(
            discountPercent: percent,
            startedAt: now
        )
        let initialState = OnboardingDiscountAttributes.ContentState(
            endsAt: endsAt,
            headline: appLocalizedString(Localizable.onboardingDiscountActivityHeadline),
            ctaLabel: appLocalizedString(Localizable.onboardingDiscountActivityCta)
        )

        persist(endsAt: endsAt, startedAt: now, percent: percent)
        expiresAt = endsAt
        discountPercent = percent
        isActive = true

        guard authorized else {
            logger.info("Live Activities not authorized; running in-app timer only.")
            return
        }

        do {
            let staleDate = endsAt.addingTimeInterval(30)
            let content = ActivityContent(state: initialState, staleDate: staleDate)
            let started = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            self.activity = started
            logger.info("Started onboarding discount Live Activity \(started.id, privacy: .public)")

            // Pre-warm StoreKit products. Without this the user's
            // first lock-screen tap pays the full `Product.products`
            // round-trip, which renders as a visible delay/spinner
            // when the discount paywall opens. We kick it off here so
            // by the time the user actually taps the banner (seconds
            // or hours later) products are cached.
            Task { await PremiumManager.shared.loadProducts() }
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// End the activity immediately. Called when:
    ///   - The user purchases successfully (no longer needs the squeeze).
    ///   - The user finishes onboarding (squeeze is onboarding-only).
    ///   - The timer naturally reaches zero.
    ///   - The user becomes premium by any other path (restore, etc.)
    ///     via `subscriptionDidBecomePremium()`.
    func end(reason: EndReason) {
        logger.info("Ending discount activity: \(reason.rawValue, privacy: .public)")

        let now = Date()
        let finalState = OnboardingDiscountAttributes.ContentState(
            endsAt: now,
            headline: reason.finalHeadline,
            ctaLabel: appLocalizedString(Localizable.onboardingDiscountActivityCta)
        )

        if let activity {
            Task { [activity] in
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }

        // Defensive: also end any siblings we don't have a handle on.
        // Happens if the manager was reset mid-flight (e.g. crash
        // recovery) and a new instance is being constructed.
        Task {
            for stale in Activity<OnboardingDiscountAttributes>.activities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }

        self.activity = nil
        self.expiresAt = nil
        self.isActive = false
        self.shouldPresentDiscountPaywall = false
        clearPersisted()
    }

    /// Polled from a SwiftUI `.onReceive(timer)` or `.task` — when the
    /// countdown crosses zero we end the activity automatically.
    func tickIfExpired(now: Date = Date()) {
        guard isActive, let expiresAt, now >= expiresAt else { return }
        end(reason: .expired)
    }

    /// Hook for callers that observe global premium status (e.g.
    /// `PremiumManager.subscriptionStatus`). Whenever a user transitions
    /// to premium by *any* path — paywall, deep link, restore, parental
    /// approval — we don't want a "limited gift" banner sitting on the
    /// lock screen contradicting that. Idempotent: no-op when inactive.
    func subscriptionDidBecomePremium() {
        guard isActive else { return }
        end(reason: .purchased)
    }

    enum EndReason: String {
        case purchased
        case onboardingFinished
        case expired
        case manual

        var finalHeadline: String {
            switch self {
            case .purchased: return appLocalizedString(Localizable.onboardingDiscountActivityFinalPurchased)
            case .onboardingFinished, .manual: return appLocalizedString(Localizable.onboardingDiscountActivityFinalClosed)
            case .expired: return appLocalizedString(Localizable.onboardingDiscountActivityFinalExpired)
            }
        }
    }

    // MARK: - Stale-activity sweep
    //
    // ActivityKit keeps Live Activities alive across rebuilds. If we
    // shipped a 24h squeeze, then iterated to 3min, the user's lock
    // screen still shows the 24h banner running against the *old*
    // widget extension binary. That stale activity:
    //   - confuses the timer story ("started at 24h, opens screen
    //     showing 3min")
    //   - renders with the previous extension's asset catalog (which
    //     is why a stale build's gray rectangle persists even after
    //     we fixed the imageset).
    //
    // On every cold launch we look at all live discount activities
    // and end any whose configured duration is more than 2× the
    // current default. The user sees a clean restart.

    private func purgeStaleActivitiesIfNeeded() {
        let currentDuration = OnboardingDiscountAttributes.defaultDuration
        let staleThreshold = currentDuration * Self.staleDurationMultiplier

        let activities = Activity<OnboardingDiscountAttributes>.activities
        for activity in activities {
            let configured = activity.content.state.endsAt
                .timeIntervalSince(activity.attributes.startedAt)
            if configured > staleThreshold {
                logger.info("Purging stale activity (configured \(configured)s vs current \(currentDuration)s)")
                Task { [activity] in
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    // MARK: - Persistence

    private func persist(endsAt: Date, startedAt: Date, percent: Int) {
        let defaults = UserDefaults.standard
        defaults.set(endsAt.timeIntervalSince1970, forKey: StorageKey.expiresAt)
        defaults.set(startedAt.timeIntervalSince1970, forKey: StorageKey.startedAt)
        defaults.set(percent, forKey: StorageKey.percent)
    }

    private func clearPersisted() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: StorageKey.expiresAt)
        defaults.removeObject(forKey: StorageKey.startedAt)
        defaults.removeObject(forKey: StorageKey.percent)
    }

    private func restoreFromDefaults() {
        let defaults = UserDefaults.standard
        let expiresRaw = defaults.double(forKey: StorageKey.expiresAt)
        guard expiresRaw > 0 else { return }

        let restored = Date(timeIntervalSince1970: expiresRaw)
        if restored <= Date() {
            clearPersisted()
            return
        }

        // Ignore persisted state that points way past the current
        // window — same staleness logic as the activity sweep.
        let startedRaw = defaults.double(forKey: StorageKey.startedAt)
        if startedRaw > 0 {
            let started = Date(timeIntervalSince1970: startedRaw)
            let configured = restored.timeIntervalSince(started)
            let staleThreshold = OnboardingDiscountAttributes.defaultDuration * Self.staleDurationMultiplier
            if configured > staleThreshold {
                logger.info("Purging stale persisted state (configured \(configured)s)")
                clearPersisted()
                return
            }
        }

        expiresAt = restored
        discountPercent = defaults.integer(forKey: StorageKey.percent).nonZero ?? 50
        isActive = true
    }

    /// On app relaunch, ActivityKit returns any still-running
    /// activities the system kept alive. Re-bind to the matching one
    /// so subsequent `update`/`end` calls target the right instance.
    /// Stale activities have already been purged at this point.
    private func rebindExistingActivityIfAny() {
        let activities = Activity<OnboardingDiscountAttributes>.activities
        if let candidate = activities.sorted(by: { $0.attributes.startedAt > $1.attributes.startedAt }).first {
            self.activity = candidate
            self.expiresAt = candidate.content.state.endsAt
            self.discountPercent = candidate.attributes.discountPercent
            self.isActive = candidate.content.state.endsAt > Date()
            logger.debug("Rebound to existing Live Activity \(candidate.id, privacy: .public)")
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

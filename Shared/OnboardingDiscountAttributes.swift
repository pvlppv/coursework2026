//
//  OnboardingDiscountAttributes.swift
//  Shared
//
//  Shared Live Activity attributes for the onboarding "limited-time 50% off"
//  squeeze. Compiled into BOTH targets via the `Shared/` synchronized
//  root group:
//    - The Sotie app target (start/update/end the activity).
//    - The SotieLiveActivityExtension target (Lock Screen + Dynamic Island).
//
//  Keeping a single source file (rather than a copy per target) prevents
//  the Codable wire format from drifting between the producer and the
//  consumer, which would silently break activity rendering.
//

import ActivityKit
import Foundation

/// Static + dynamic state for the onboarding discount Live Activity.
///
/// Static (`OnboardingDiscountAttributes`):
///   - `discountPercent`: the percent-off being offered (e.g. 50).
///   - `startedAt`: when the squeeze began. Lets the widget render a stable
///     `ProgressView(timerInterval:)` that counts down across updates.
///
/// Dynamic (`ContentState`):
///   - `endsAt`: when the offer expires. The widget binds a SwiftUI
///     `Text(timerInterval:countsDown:)` to this date for a live-ticking
///     timer that doesn't require periodic push updates.
///   - `headline`: short copy line ("Your 50% off is waiting").
public struct OnboardingDiscountAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        public var endsAt: Date
        public var headline: String
        /// Localized label for the "Open my gift" CTA pill in the
        /// widget. Lives on the dynamic state because the widget
        /// extension has no access to the app's localization stack
        /// (separate target, separate bundle). The app injects the
        /// already-localized string when starting/updating the
        /// activity, and the widget renders it verbatim.
        public var ctaLabel: String

        public init(endsAt: Date, headline: String, ctaLabel: String) {
            self.endsAt = endsAt
            self.headline = headline
            self.ctaLabel = ctaLabel
        }
    }

    public let discountPercent: Int
    public let startedAt: Date

    public init(discountPercent: Int, startedAt: Date) {
        self.discountPercent = discountPercent
        self.startedAt = startedAt
    }
}

public extension OnboardingDiscountAttributes {
    /// How long the Live Activity sits on the lock screen after
    /// onboarding starts. Purely a visual ad — no urgency math is
    /// derived from it. The discount paywall runs its own short
    /// countdown when it actually opens.
    nonisolated static let defaultDuration: TimeInterval = 24 * 60 * 60

    /// Deep-link URL the widget opens when tapped. Routed by
    /// `NavigationRouter.handleDeepLink(url:)` to present the discount paywall.
    nonisolated static let deepLinkURL = URL(string: "sotiejournal://onboarding/discount")!
}

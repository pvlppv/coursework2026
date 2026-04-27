//
//  OnboardingDiscountLiveActivity.swift
//  SotieLiveActivity
//
//  Lock Screen + Dynamic Island for the onboarding "limited-time gift"
//  squeeze. Layout follows the reference (icon-left, content-right) but
//  rendered in Sotie's monochrome palette — orange becomes `.primary`,
//  text on the CTA pill uses the system background colour. The actual
//  gift visual is a real PNG asset (`Present`) shipped via the shared
//  asset catalog so both the app target and the widget extension see
//  it.
//
//  The whole banner is a single tap target. Tapping deep-links into
//  the app via `widgetURL(OnboardingDiscountAttributes.deepLinkURL)`,
//  which the router resolves into the discount paywall sheet.
//
//  Why no `Timer`: SwiftUI's `Text(timerInterval:countsDown:)` ticks
//  client-side, no push updates required.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct OnboardingDiscountLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OnboardingDiscountAttributes.self) { context in
            // Lock Screen banner. The whole banner taps through to the app.
            LockScreenView(context: context)
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(OnboardingDiscountAttributes.deepLinkURL)

        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded
                //
                // The expanded island is two regions wide (leading +
                // trailing) with an optional bottom span. We use:
                //   leading  → present icon (anchor)
                //   trailing → headline above the timer (live updates)
                //   bottom   → Open my gift CTA pill
                // We deliberately omit the `.center` region: in
                // ActivityKit, leading/trailing regions hard-clamp to
                // ~25% width and a center region squeezes them to
                // unreadable widths on the lock-screen sized island.
                DynamicIslandExpandedRegion(.leading) {
                    PresentImage(size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.headline)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(timerInterval: timerRange(context: context),
                             countsDown: true,
                             showsHours: true)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .font(.system(size: 22, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer()
                        OpenPill(label: context.state.ctaLabel)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                PresentImage(size: 18)
            } compactTrailing: {
                // 24h range needs `showsHours: true` — without it
                // SwiftUI renders the elapsed minutes verbatim
                // ("1439:NN") and overflows. With hours visible the
                // format is `H:MM:SS`, which fits in 56pt.
                Text(timerInterval: timerRange(context: context),
                     countsDown: true,
                     showsHours: true)
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: 56, alignment: .trailing)
            } minimal: {
                PresentImage(size: 18)
            }
            .widgetURL(OnboardingDiscountAttributes.deepLinkURL)
            .keylineTint(.primary)
        }
    }

    /// SwiftUI uses this range to render a self-updating countdown.
    /// Clamp `endsAt` strictly above `startedAt` to avoid `ClosedRange`
    /// trapping if persistence ever returns the same instant twice.
    private func timerRange(context: ActivityViewContext<OnboardingDiscountAttributes>) -> ClosedRange<Date> {
        let start = context.attributes.startedAt
        let end = max(context.state.endsAt, start.addingTimeInterval(1))
        return start...end
    }
}

// MARK: - Lock Screen
//
// Anatomy: present pinned to the leading edge as the only left-aligned
// element, everything else hugs the trailing edge.
//
//   ┌────────┐                  A surprise limited gift for you
//   │   📦   │                                  03:00
//   │  IMAGE │                          ╭───────────────╮
//   └────────┘                          │  Open my gift │
//                                       ╰───────────────╯

private struct LockScreenView: View {
    let context: ActivityViewContext<OnboardingDiscountAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PresentImage(size: 76)

            VStack(alignment: .trailing, spacing: 6) {
                Text(context.state.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text(timerInterval: timerRange,
                     countsDown: true,
                     showsHours: true)
                    .monospacedDigit()
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    // `Text(timerInterval:)` renders its digits inside
                    // a greedy container that defaults to leading
                    // alignment. Without this the timer drifts left
                    // even when the parent frame says trailing.
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                OpenPill(label: context.state.ctaLabel)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var timerRange: ClosedRange<Date> {
        let start = context.attributes.startedAt
        let end = max(context.state.endsAt, start.addingTimeInterval(1))
        return start...end
    }
}

// MARK: - Present image
//
// Wraps the shared `Present` asset (3D gift-box render) with a fixed
// frame and `scaledToFit`. The asset ships with `template-rendering-
// intent: original` so iOS preserves the image's own colours instead
// of tinting it as a template (which is what made the previous build
// render as a solid grey rectangle).

private struct PresentImage: View {
    let size: CGFloat

    var body: some View {
        // `.renderingMode(.original)` forces full-color rendering even
        // in Live Activity contexts that would otherwise treat the
        // image as a template (resulting in a flat gray rectangle).
        // Belt-and-braces with the `template-rendering-intent:
        // original` flag on the imageset.
        Image("Present")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

// MARK: - "Open my gift" CTA pill
//
// Mirrors the orange CTA from the reference. We use `.primary` (black
// in light mode, white in dark) for the fill so the pill stays
// on-brand, render the label in the system background colour for
// punch. No leading emoji — the pointing-finger reads weird against
// our monochrome system. Solid fill, no stroke, no glow.
//
// Live Activities can't host arbitrary tappable controls without
// `AppIntent`s. The whole banner is the tap target.
//
// Label is passed in from the content state because the widget
// extension target has no access to the app's localization stack.

private struct OpenPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color(.systemBackground))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous).fill(.primary)
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}

//
//  PaywallLegalFooter.swift
//  Sotie
//
//  Reusable "Just $X per year ($Y/mo)" + "Terms · Privacy · Restore" footer
//  used on every onboarding screen that introduces the trial / paywall flow.
//  Keeps copy and layout consistent across the funnel and gives the user an
//  always-visible restore path required by App Store policy.
//
//  Two layouts:
//   - `.brief` (TryNow / TrialReminder): pricing tease + Terms·Privacy·Restore.
//   - `.compact` (paywall itself): just Terms·Privacy·Restore (the paywall has
//     its own pricing/disclosure rendering above this).
//

import SwiftUI

struct PaywallLegalFooter: View {
    enum Layout {
        case brief    // pricing tease + links
        case compact  // links only
    }

    /// Caller must trigger the actual purchase restore via PremiumManager.
    let onRestore: () -> Void

    /// "Just $68.99 per year ($5.75/mo)" — only shown for `.brief` layout.
    /// Caller is responsible for formatting; pass nil to omit.
    var pricingTease: String? = nil

    var layout: Layout = .brief

    var body: some View {
        VStack(spacing: 6) {
            if layout == .brief, let pricingTease {
                Text(pricingTease)
                    .font(.system(size: 12, weight: .regular))
                    .themeText(.tertiary)
                    .multilineTextAlignment(.center)
            }

            // "Terms · Privacy · Restore" — tight spacing, small dot separators
            HStack(spacing: 6) {
                Link(
                    appLocalizedString(Localizable.premiumTerms),
                    destination: URL(string: "https://sotie.app/terms")!
                )
                .font(.system(size: 11))
                .themeText(.tertiary)

                Text("·")
                    .font(.system(size: 11))
                    .themeText(.tertiary)

                Link(
                    appLocalizedString(Localizable.premiumPrivacy),
                    destination: URL(string: "https://sotie.app/privacy")!
                )
                .font(.system(size: 11))
                .themeText(.tertiary)

                Text("·")
                    .font(.system(size: 11))
                    .themeText(.tertiary)

                Button {
                    HapticManager.shared.light()
                    onRestore()
                } label: {
                    Text(appLocalizedString(Localizable.premiumRestore))
                        .font(.system(size: 11))
                        .themeText(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding-paywall-restore")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: 24) {
        PaywallLegalFooter(
            onRestore: {},
            pricingTease: "Just $68.99 per year ($5.75/mo)",
            layout: .brief
        )

        PaywallLegalFooter(onRestore: {}, layout: .compact)
    }
    .padding()
    .background(Color.theme.backgroundPrimary)
}

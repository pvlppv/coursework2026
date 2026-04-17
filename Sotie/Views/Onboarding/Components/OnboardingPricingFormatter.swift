//
//  OnboardingPricingFormatter.swift
//  Sotie
//
//  Pricing-tease formatter shared across onboarding screens that mention
//  the trial without owning the full paywall layout (TryNowDemo,
//  TrialReminder). Reads the annual product price from PremiumManager and
//  builds a "Just $X per year ($Y/mo)" string.
//

import Foundation
import StoreKit

enum OnboardingPricingFormatter {

    /// "Just $68.99 per year ($5.75/mo)" — locale-aware where possible.
    /// Falls back to a generic line if products haven't loaded.
    static func teaseLine(for products: [Product]) -> String {
        guard let annual = products.first(where: { $0.id == PremiumProduct.annual.rawValue }) else {
            // Products not loaded yet — give a safe fallback that reads naturally.
            return appLocalizedString(Localizable.onboardingFlowFooterPricingFallback)
        }

        let monthlyEq = monthlyEquivalent(for: annual)

        return appLocalizedString(
            Localizable.onboardingFlowFooterPricingFull,
            arguments: annual.displayPrice, monthlyEq
        )
    }

    /// "$5.75/mo" line — formatted using the product's currency.
    private static func monthlyEquivalent(for annual: Product) -> String {
        let monthly = NSDecimalNumber(decimal: annual.price)
            .dividing(by: NSDecimalNumber(value: 12))

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = annual.priceFormatStyle.locale
        formatter.currencyCode = annual.priceFormatStyle.currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        let formatted = formatter.string(from: monthly) ?? "\(monthly)"
        return appLocalizedString(
            Localizable.onboardingFlowFooterPricingPerMonth,
            arguments: formatted
        )
    }

    /// "$0.00" / "0,00 ₽" / "¥0" — locale-aware zero in the user's currency.
    /// Used for the "Try for $0.00" CTA. Reads currency from any loaded
    /// subscription product; falls back to a plain "$0.00" if none.
    static func zeroPriceString(for products: [Product]) -> String {
        guard let referenceProduct = products.first else {
            return "$0.00"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = referenceProduct.priceFormatStyle.locale
        formatter.currencyCode = referenceProduct.priceFormatStyle.currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        return formatter.string(from: NSDecimalNumber.zero) ?? "$0.00"
    }
}

import Foundation
import Observation

/// Abstraction over the paid/free state, injected into views. Concrete
/// implementations: `RevenueCatSubscriptionService` (real) and
/// `PreviewSubscriptionService` (fake, for #Preview and tests).
///
/// Views MUST NOT import RevenueCat directly. All Purchases interaction
/// funnels through this protocol so the payment provider is swappable and
/// previews don't hit the network.
@MainActor
protocol SubscriptionService: AnyObject, Observable {
    /// True when the customer has the `pro` entitlement active. Refreshed
    /// automatically when RevenueCat's CustomerInfo stream fires.
    var isPro: Bool { get }

    /// The current offering (containing `pro_monthly` and `pro_yearly`
    /// packages), or nil if not yet fetched / offline / not configured.
    var offering: SubscriptionOffering? { get }

    /// Force a refresh — call after network reconnect or from a "Refresh"
    /// button in the paywall. No-op if a fetch is already in flight.
    func refresh() async

    /// Purchase a specific package. Returns whether the customer is now Pro.
    /// Throws `SubscriptionServiceError` on user cancellation, network failure,
    /// declined payment, etc.
    func purchase(_ package: SubscriptionPackage) async throws -> Bool

    /// Restore prior purchases (mandatory App Store button on paywalls).
    /// Returns whether Pro was found and restored.
    @discardableResult
    func restorePurchases() async throws -> Bool
}

/// Provider-agnostic offering: two packages (monthly + yearly).
/// Field names match what the paywall needs — no RC types leak through.
struct SubscriptionOffering: Equatable, Sendable {
    var monthly: SubscriptionPackage?
    var yearly: SubscriptionPackage?
}

/// Provider-agnostic package. All price data is pre-formatted for the local
/// storefront so views don't format prices themselves.
struct SubscriptionPackage: Equatable, Hashable, Sendable, Identifiable {
    /// Stable ID for ForEach / picker selection (e.g. "pro_yearly").
    var id: String
    /// Localised price like "£29.99".
    var priceString: String
    /// Localised period like "per year" / "per month".
    var periodString: String
    /// Localised intro-offer copy like "7-day free trial, then £29.99/year".
    /// Nil when the current customer isn't eligible for an intro offer.
    var introOfferString: String?
    /// Optional badge like "50% OFF" for the yearly package on the paywall.
    var savingsBadge: String?
}

/// Plain-language errors surfaced to the paywall. Never leaks RC error codes.
enum SubscriptionServiceError: Error, LocalizedError, Equatable {
    case notConfigured
    case cancelled          // user tapped Cancel in the native sheet
    case paymentPending     // Ask to Buy, awaiting parental approval, etc.
    case declined           // payment method declined
    case network
    case unknown

    var errorDescription: String? {
        switch self {
        case .notConfigured:  "In-app purchases aren't set up yet. Try again after updating."
        case .cancelled:      nil       // silent — user meant to cancel
        case .paymentPending: "Waiting on approval. We'll unlock Pro as soon as it clears."
        case .declined:       "The payment was declined. Try a different method."
        case .network:        "Can't reach the App Store. Check your connection and try again."
        case .unknown:        "Something went wrong. Try again in a moment."
        }
    }
}

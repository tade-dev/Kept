import Foundation

/// Abstraction over the paid/free state. Concrete implementations:
/// `RevenueCatSubscriptionService` (real) and `PreviewSubscriptionService`
/// (fake, for #Preview and tests).
///
/// Views MUST NOT import RevenueCat directly. All Purchases interaction
/// funnels through this protocol so the payment provider is swappable and
/// previews don't hit the network.
///
/// **Not @Observable on purpose.** Swift's `@Observable` macro registers
/// observation via static type analysis and can't see through `any` /
/// existentials. So this protocol is a plain interface; state changes are
/// pushed via `onChange` to `SubscriptionAccess`, which is the actual
/// @Observable wrapper the view layer talks to.
@MainActor
protocol SubscriptionService: AnyObject {
    /// True when the customer has the `pro` entitlement active.
    var isPro: Bool { get }

    /// The current offering (containing `pro_monthly` and `pro_yearly`
    /// packages), or nil if not yet fetched / offline / not configured.
    var offering: SubscriptionOffering? { get }

    /// Non-nil when Apple has flagged a billing issue on the active Pro
    /// entitlement — card declined, expired, etc. The subscription is still
    /// technically valid (`isPro == true`) during the grace period; use this
    /// to show a soft nudge asking the user to fix their payment before it
    /// actually lapses.
    var billingIssue: BillingIssue? { get }

    /// Opaque, stable customer identifier used by the payment provider.
    /// Exposed for support-ticket copy — never rendered as primary UI.
    var appUserID: String { get }

    /// Handler invoked (on the main actor) whenever isPro / offering /
    /// appUserID change. `SubscriptionAccess` wires this up in its init and
    /// mirrors the values into its own @Observable properties so the view
    /// layer stays reactive.
    var onChange: (@MainActor () -> Void)? { get set }

    /// Force a refresh — call after network reconnect or from a "Refresh"
    /// button. No-op if a fetch is already in flight.
    func refresh() async

    /// Purchase a specific package. Returns whether the customer is now Pro.
    /// Throws `SubscriptionServiceError` on user cancellation, network
    /// failure, declined payment, etc.
    func purchase(_ package: SubscriptionPackage) async throws -> Bool

    /// Restore prior purchases (mandatory App Store button on paywalls).
    /// Returns whether Pro was found and restored.
    @discardableResult
    func restorePurchases() async throws -> Bool
}

/// Provider-agnostic offering: recurring packages (monthly + yearly) plus an
/// optional lifetime one-shot. `lifetime` is a non-consumable IAP surfaced
/// alongside the subscriptions so users who won't tolerate recurring billing
/// still have a way in.
struct SubscriptionOffering: Equatable, Sendable {
    var monthly: SubscriptionPackage?
    var yearly: SubscriptionPackage?
    var lifetime: SubscriptionPackage?
}

/// Snapshot of a live billing problem on the customer's subscription. Emitted
/// when Apple has flagged a payment failure and we're inside the grace
/// window — the entitlement is still active but will lapse if the user
/// doesn't fix their card.
struct BillingIssue: Equatable, Sendable {
    /// When Apple detected the billing failure.
    var detectedAt: Date
    /// When the grace period ends — after this the entitlement is revoked.
    /// Nil when the provider doesn't expose an end date.
    var gracePeriodEndsAt: Date?
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

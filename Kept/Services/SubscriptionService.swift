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

    /// The current offering, or nil if not yet fetched / offline / not configured.
    /// The paywall shows yearly and lifetime only. A monthly package may still
    /// be present on the offering during rollout; `PaywallCatalog` filters it out.
    var offering: SubscriptionOffering? { get }

    /// True after a fetch failed and no offering is available. Distinct from
    /// the initial load, which leaves this false while `offering` is nil.
    var offeringLoadFailed: Bool { get }

    /// Non-nil when Apple has flagged a billing issue on the active Pro
    /// entitlement — card declined, expired, etc. The subscription is still
    /// technically valid (`isPro == true`) during the grace period; use this
    /// to show a soft nudge asking the user to fix their payment before it
    /// actually lapses.
    var billingIssue: BillingIssue? { get }

    /// Non-nil when the customer's Pro access is time-limited (an Apple
    /// intro trial or one of our promotional grants) and thus will lapse
    /// unless they buy. Used by the offer-notification scheduler to plant
    /// a "your Pro access ends in X days" nudge.
    var proAccessExpiry: ProAccessExpiry? { get }

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

    /// Asks Kept's Cloudflare Worker to grant this customer a 7-day
    /// promotional Pro entitlement via RevenueCat's REST API. Called by the
    /// engagement-based trial-boost flow — the app decides the customer is
    /// engaged enough to deserve it, then this method actually mints the
    /// entitlement. Returns once RC has confirmed the grant; the local
    /// `isPro` update lands via the normal `customerInfoStream` shortly
    /// after. Throws on network / auth failure.
    func grantTrialBoost() async throws
}

/// Provider-agnostic offering. `monthly` may still be filled from the store
/// during rollout; the paywall must not display it. `lifetime` is a
/// non-consumable surfaced as a peer of yearly.
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

/// Details on when Kept Pro will lapse for a customer whose access is
/// time-limited (Apple intro trial OR one of our promotional grants).
/// Only non-nil while the entitlement is genuinely temporary — a paid
/// auto-renewing sub returns nil because it doesn't need a "ending soon"
/// nudge (it renews itself).
struct ProAccessExpiry: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        /// Apple's built-in intro offer / free trial on a subscription.
        case trial
        /// A RevenueCat promotional entitlement (e.g. our trial boost).
        case promotional
    }

    var endsAt: Date
    var reason: Reason
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
    /// Intro-offer sentence built from the store product (trial length and
    /// `localizedPriceString`). Nil when this customer isn't eligible.
    var introOfferString: String?
    /// Short free-trial label built from the store intro period, like
    /// "7 days free". Nil unless the intro is a free trial.
    var introBadge: String? = nil
    /// Store intro free-trial length. Nil unless the intro is a free trial.
    /// The paywall uses this with `priceString` for "Free for N days".
    var introPeriodCount: Int? = nil
    /// Store intro unit already pluralized ("day" / "days"). Nil with the count.
    var introPeriodUnit: String? = nil
    /// Unused. Kept so older call sites still compile. The paywall does not
    /// show a savings percentage — that maths compared yearly to monthly.
    var savingsBadge: String?
    /// Non-nil when the customer is a lapsed subscriber Apple has flagged as
    /// eligible for a win-back offer on this specific package. Populated from
    /// RC's `eligibleWinBackOffers(forProduct:)` (iOS 18+). Views should read
    /// this to show a "welcome back" banner + apply the offer at purchase
    /// time; when nil the package purchases at its normal price.
    var winBackOffer: WinBackOffer?
}

/// Discount details for a win-back offer the current customer is eligible
/// for. Purely display data — the provider-specific offer object stays
/// behind the service boundary so the view layer never touches RevenueCat
/// or StoreKit types.
struct WinBackOffer: Equatable, Hashable, Sendable {
    /// Apple's offer identifier (matches what was configured in App Store
    /// Connect). The concrete service uses this to look the offer back up
    /// when calling `purchase(_:)`.
    var identifier: String
    /// Pre-formatted discounted price like "£2.49" or "Free".
    var priceString: String
    /// Short human summary for the paywall — "50% off first month",
    /// "1 month free", etc. Generated in the service, not the view.
    var summary: String
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

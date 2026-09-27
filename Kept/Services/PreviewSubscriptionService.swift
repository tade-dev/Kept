import Foundation
import Observation

/// In-memory fake for #Preview and unit tests. Never touches RevenueCat.
///
/// Flip `isPro` from outside a preview to exercise the Pro vs Free codepaths
/// without mocking Purchases. The `purchase(_:)` and `restorePurchases()`
/// methods mutate `isPro` synchronously so tests can assert without waits.
@MainActor
final class PreviewSubscriptionService: SubscriptionService {
    var isPro: Bool { didSet { onChange?() } }
    var offering: SubscriptionOffering? { didSet { onChange?() } }
    var offeringLoadFailed: Bool { didSet { onChange?() } }
    var billingIssue: BillingIssue? { didSet { onChange?() } }
    var proAccessExpiry: ProAccessExpiry? { didSet { onChange?() } }
    var appUserID: String = "preview_app_user"
    var onChange: (@MainActor () -> Void)?
    /// Override to make `purchase(_:)` throw a specific error in previews / tests.
    var nextPurchaseError: SubscriptionServiceError?

    init(
        isPro: Bool = false,
        offering: SubscriptionOffering? = .kept_default,
        billingIssue: BillingIssue? = nil,
        proAccessExpiry: ProAccessExpiry? = nil,
        offeringLoadFailed: Bool = false,
        nextPurchaseError: SubscriptionServiceError? = nil
    ) {
        self.isPro = isPro
        self.offering = offering
        self.offeringLoadFailed = offeringLoadFailed
        self.billingIssue = billingIssue
        self.proAccessExpiry = proAccessExpiry
        self.nextPurchaseError = nextPurchaseError
    }

    func refresh() async { /* no-op */ }

    func purchase(_ package: SubscriptionPackage) async throws -> Bool {
        if let err = nextPurchaseError {
            nextPurchaseError = nil
            throw err
        }
        isPro = true
        return true
    }

    @discardableResult
    func restorePurchases() async throws -> Bool {
        if let err = nextPurchaseError {
            nextPurchaseError = nil
            throw err
        }
        return isPro
    }

    func grantTrialBoost() async throws {
        // In previews / tests just flip isPro so the celebration overlay
        // and any Pro-gated UI reflect the granted entitlement.
        isPro = true
    }
}

extension SubscriptionOffering {
    /// Preview offering with a yearly win-back offer so the paywall banner
    /// renders without a live RevenueCat customer. Not a monthly plan.
    static var kept_withWinBack: SubscriptionOffering {
        var o = kept_default
        o.yearly?.winBackOffer = WinBackOffer(
            identifier: "winback_yearly",
            priceString: o.yearly?.priceString ?? "",
            summary: "Welcome back offer"
        )
        return o
    }

    /// Preview stand-in for a store offering. `priceString` values imitate
    /// `storeProduct.localizedPriceString` so SwiftUI previews can render;
    /// they are not product prices and the paywall never reads them in the app.
    /// Monthly is omitted — the paywall filters it out even if a fixture includes it.
    static let kept_default = SubscriptionOffering(
        monthly: nil,
        yearly: SubscriptionPackage(
            id: "pro_yearly",
            priceString: "£41.99",
            periodString: "per year",
            introOfferString: "7-day free trial, then £41.99/year",
            introBadge: "7 days free",
            introPeriodCount: 7,
            introPeriodUnit: "days",
            savingsBadge: nil
        ),
        lifetime: SubscriptionPackage(
            id: "pro_lifetime",
            priceString: "£99.99",
            periodString: "one-time",
            introOfferString: nil,
            savingsBadge: nil
        )
    )
}

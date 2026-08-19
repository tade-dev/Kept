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
    var appUserID: String = "preview_app_user"
    var onChange: (@MainActor () -> Void)?
    /// Override to make `purchase(_:)` throw a specific error in previews / tests.
    var nextPurchaseError: SubscriptionServiceError?

    init(
        isPro: Bool = false,
        offering: SubscriptionOffering? = .kept_default,
        nextPurchaseError: SubscriptionServiceError? = nil
    ) {
        self.isPro = isPro
        self.offering = offering
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
}

extension SubscriptionOffering {
    /// Default preview offering — mirrors real Kept Pro pricing.
    static let kept_default = SubscriptionOffering(
        monthly: SubscriptionPackage(
            id: "pro_monthly",
            priceString: "£4.99",
            periodString: "per month",
            introOfferString: nil,
            savingsBadge: nil
        ),
        yearly: SubscriptionPackage(
            id: "pro_yearly",
            priceString: "£29.99",
            periodString: "per year",
            introOfferString: "7-day free trial, then £29.99/year",
            savingsBadge: "50% OFF"
        )
    )
}

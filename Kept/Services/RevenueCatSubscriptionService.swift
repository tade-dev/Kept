import Foundation
import Observation
import RevenueCat

/// Concrete `SubscriptionService` backed by RevenueCat's Purchases SDK.
///
/// Isolation: all RC types (`Offerings`, `Package`, `PurchasesError`, etc.)
/// stay in this file. Callers see only the plain types from
/// `SubscriptionService.swift`.
///
/// Listens for CustomerInfo updates via `customerInfoStream` so `isPro`
/// stays fresh without polling. The stream keeps running for the app's
/// lifetime — no cancellation is needed since this service is a singleton
/// held by the App.
@MainActor
final class RevenueCatSubscriptionService: SubscriptionService {
    private(set) var isPro: Bool = false
    private(set) var offering: SubscriptionOffering?
    var appUserID: String { Purchases.shared.appUserID }
    var onChange: (@MainActor () -> Void)?

    private var listenerTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init() {
        // Prime state from cached CustomerInfo if available (avoids a false
        // "free" flicker on cold launch when the customer is actually Pro).
        Task { [weak self] in
            if let info = try? await Purchases.shared.customerInfo() {
                self?.applyCustomerInfo(info)
            }
        }

        // Live stream of CustomerInfo updates — fires on entitlement changes,
        // purchase completion, restore, expiry, etc.
        listenerTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.applyCustomerInfo(info)
            }
        }

        // Fetch offerings on init. Failure is silent — paywall shows empty
        // state and a retry.
        Task { [weak self] in await self?.refresh() }
    }

    // No explicit deinit — Tasks hold `[weak self]` so they no-op after
    // dealloc. Touching main-actor state from a nonisolated deinit is
    // disallowed in Swift 6.

    func refresh() async {
        // De-dup: if a refresh is already running, wait for it instead of
        // launching a second parallel fetch.
        if let existing = refreshTask, !existing.isCancelled {
            _ = await existing.value
            return
        }
        let task = Task { [weak self] in
            do {
                let offerings = try await Purchases.shared.offerings()
                self?.offering = Self.mapOfferings(offerings)
                self?.onChange?()
            } catch {
                // Silent — paywall shows retry.
            }
        }
        refreshTask = task
        _ = await task.value
        refreshTask = nil
    }

    func purchase(_ package: SubscriptionPackage) async throws -> Bool {
        guard let rcPackage = try await resolveRCPackage(for: package.id) else {
            throw SubscriptionServiceError.notConfigured
        }
        do {
            let result = try await Purchases.shared.purchase(package: rcPackage)
            if result.userCancelled {
                throw SubscriptionServiceError.cancelled
            }
            applyCustomerInfo(result.customerInfo)

            // Sandbox can hand back a CustomerInfo whose entitlement isn't
            // yet marked active (server-side propagation lag). Kick off a
            // background refetch so `isPro` catches up shortly. Do NOT gate
            // this method's return on the just-returned entitlement — a
            // non-cancelled, non-thrown call means the transaction went
            // through and the customer is (or is about to be) Pro.
            Task { [weak self] in
                if let info = try? await Purchases.shared.customerInfo() {
                    self?.applyCustomerInfo(info)
                }
            }
            return true
        } catch let error as ErrorCode {
            throw Self.mapErrorCode(error)
        } catch {
            throw Self.mapUnknownError(error)
        }
    }

    @discardableResult
    func restorePurchases() async throws -> Bool {
        do {
            let info = try await Purchases.shared.restorePurchases()
            applyCustomerInfo(info)
            return info.entitlements[Self.entitlementIdentifier]?.isActive ?? false
        } catch let error as ErrorCode {
            throw Self.mapErrorCode(error)
        } catch {
            throw Self.mapUnknownError(error)
        }
    }

    // MARK: - Internal

    /// Must match the entitlement identifier configured in the RevenueCat
    /// dashboard for the current project. Case-sensitive — RC treats "Kept Pro"
    /// and "pro" as distinct.
    private static let entitlementIdentifier = "Kept Pro"

    private func applyCustomerInfo(_ info: CustomerInfo) {
        let active = info.entitlements[Self.entitlementIdentifier]?.isActive ?? false
        let changed = active != isPro
        if changed { isPro = active }
        onChange?()
    }

    private func resolveRCPackage(for id: String) async throws -> Package? {
        // Prefer the cached offering; fall back to a fresh fetch.
        if let cached = try? await Purchases.shared.offerings().current {
            return cached.availablePackages.first(where: { $0.storeProduct.productIdentifier == id })
        }
        return nil
    }

    private static func mapOfferings(_ offerings: Offerings) -> SubscriptionOffering? {
        guard let current = offerings.current else { return nil }

        let monthlyRC = current.availablePackages
            .first(where: { $0.storeProduct.productIdentifier == "pro_monthly" })
        let yearlyRC = current.availablePackages
            .first(where: { $0.storeProduct.productIdentifier == "pro_yearly" })

        let monthly = monthlyRC.map { package -> SubscriptionPackage in
            SubscriptionPackage(
                id: package.storeProduct.productIdentifier,
                priceString: package.storeProduct.localizedPriceString,
                periodString: "per month",
                introOfferString: introCopy(for: package, fallbackPeriod: "month"),
                savingsBadge: nil
            )
        }

        let yearly = yearlyRC.map { package -> SubscriptionPackage in
            let badge: String? = {
                guard let m = monthlyRC else { return nil }
                let monthlyPer12 = m.storeProduct.price * Decimal(12)
                let yearlyPrice = package.storeProduct.price
                guard monthlyPer12 > 0 else { return nil }
                let saved = (monthlyPer12 - yearlyPrice) / monthlyPer12
                let pctNS = NSDecimalNumber(decimal: saved * Decimal(100))
                let pct = Int(pctNS.doubleValue.rounded())
                return pct >= 10 ? "\(pct)% OFF" : nil
            }()
            return SubscriptionPackage(
                id: package.storeProduct.productIdentifier,
                priceString: package.storeProduct.localizedPriceString,
                periodString: "per year",
                introOfferString: introCopy(for: package, fallbackPeriod: "year"),
                savingsBadge: badge
            )
        }

        return SubscriptionOffering(monthly: monthly, yearly: yearly)
    }

    private static func introCopy(for package: Package, fallbackPeriod: String) -> String? {
        guard let intro = package.storeProduct.introductoryDiscount else { return nil }
        switch intro.paymentMode {
        case .freeTrial:
            let days = intro.subscriptionPeriod.value
            let unit = periodString(intro.subscriptionPeriod.unit, count: days)
            return "\(days)-\(unit) free trial, then \(package.storeProduct.localizedPriceString)/\(fallbackPeriod)"
        case .payAsYouGo, .payUpFront:
            return "\(intro.localizedPriceString) intro, then \(package.storeProduct.localizedPriceString)/\(fallbackPeriod)"
        }
    }

    private static func periodString(_ unit: SubscriptionPeriod.Unit, count: Int) -> String {
        switch unit {
        case .day:   count == 1 ? "day" : "days"
        case .week:  count == 1 ? "week" : "weeks"
        case .month: count == 1 ? "month" : "months"
        case .year:  count == 1 ? "year" : "years"
        }
    }

    private static func mapErrorCode(_ error: ErrorCode) -> SubscriptionServiceError {
        switch error {
        case .purchaseCancelledError:            .cancelled
        case .paymentPendingError:               .paymentPending
        case .productNotAvailableForPurchaseError,
             .storeProblemError,
             .productAlreadyPurchasedError:      .notConfigured
        case .networkError, .offlineConnectionError: .network
        default: .unknown
        }
    }

    private static func mapUnknownError(_ error: Error) -> SubscriptionServiceError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .network }
        return .unknown
    }
}

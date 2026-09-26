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
    private(set) var billingIssue: BillingIssue?
    private(set) var proAccessExpiry: ProAccessExpiry?
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
                var mapped = Self.mapOfferings(offerings)
                // Merge in win-back offer eligibility (iOS 18+). Runs in
                // parallel to keep the paywall's `.task` fast; if the SDK
                // isn't available or the user isn't eligible, packages come
                // back with `winBackOffer == nil` and the paywall renders
                // normally.
                if let current = offerings.current {
                    mapped = await Self.attachingWinBackOffers(to: mapped, from: current)
                }
                self?.offering = mapped
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
            // If the caller's package has a win-back offer attached, look
            // it up on the RC package and route the purchase through the
            // PurchaseParams builder so Apple applies the discount. Falls
            // back to the vanilla purchase path when no offer is set
            // (which is the normal case for new customers).
            let result: PurchaseResultData
            if let winBackID = package.winBackOffer?.identifier,
               let rcOffer = try await eligibleWinBackOffer(for: rcPackage, matching: winBackID) {
                let params = PurchaseParams.Builder(package: rcPackage)
                    .with(winBackOffer: rcOffer)
                    .build()
                result = try await Purchases.shared.purchase(params)
            } else {
                result = try await Purchases.shared.purchase(package: rcPackage)
            }
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

    func grantTrialBoost() async throws {
        guard let config = CloudExtractConfiguration.fromBundle()
                ?? CloudExtractConfiguration.fromEnvironment() else {
            throw SubscriptionServiceError.notConfigured
        }
        let appUserID = Purchases.shared.appUserID
        let url = config.baseURL.appendingPathComponent("pro-boost")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.secret)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = max(config.timeout, 15)
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["appUserID": appUserID]
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain { throw SubscriptionServiceError.network }
            throw SubscriptionServiceError.unknown
        }

        guard let http = response as? HTTPURLResponse else {
            throw SubscriptionServiceError.unknown
        }
        switch http.statusCode {
        case 200, 201:
            _ = data  // response body ignored — success signal is the status
        case 401, 403:
            throw SubscriptionServiceError.notConfigured
        default:
            throw SubscriptionServiceError.unknown
        }

        // RC's live customerInfoStream will fire once its cache picks up the
        // new promotional entitlement, but we can nudge it faster by asking
        // for a fresh fetch right now — cuts the "granted, but paywall still
        // says Free" gap from ~seconds to sub-second.
        if let info = try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent) {
            applyCustomerInfo(info)
        }
    }

    // MARK: - Internal

    /// Must match the entitlement identifier configured in the RevenueCat
    /// dashboard for the current project. Case-sensitive — RC treats "Kept Pro"
    /// and "pro" as distinct.
    private static let entitlementIdentifier = "Kept Pro"

    private func applyCustomerInfo(_ info: CustomerInfo) {
        let entitlement = info.entitlements[Self.entitlementIdentifier]
        let active = entitlement?.isActive ?? false
        if active != isPro { isPro = active }

        // Grace-period detection. RevenueCat surfaces `billingIssueDetectedAt`
        // whenever Apple has flagged a payment failure on this entitlement.
        // We only surface it to the UI while the entitlement is STILL active
        // (i.e. inside the grace window) — once it expires the user is just
        // "free" again and the banner would be misleading.
        if let entitlement, active, let detectedAt = entitlement.billingIssueDetectedAt {
            billingIssue = BillingIssue(
                detectedAt: detectedAt,
                gracePeriodEndsAt: entitlement.expirationDate
            )
        } else if billingIssue != nil {
            billingIssue = nil
        }

        // Time-limited Pro access (trial or promotional grant) — expose the
        // expiry so the notification scheduler can plant an "ending soon"
        // reminder. Paid auto-renewing subs return nil here since they
        // don't need a nudge to convert.
        //
        // Two separate RC enums matter here: `periodType` distinguishes
        // trial / intro from a normal paid period, while `store` tells us
        // whether the entitlement came from Apple's IAP flow or was granted
        // promotionally via our `/pro-boost` endpoint. Promo grants are
        // never auto-renewing, so we always want to nudge; paid subs with
        // `willRenew == true` are silent by design.
        if let entitlement, active, let endsAt = entitlement.expirationDate {
            if entitlement.store == .promotional {
                proAccessExpiry = ProAccessExpiry(endsAt: endsAt, reason: .promotional)
            } else if entitlement.periodType == .trial || entitlement.periodType == .intro {
                proAccessExpiry = ProAccessExpiry(endsAt: endsAt, reason: .trial)
            } else {
                proAccessExpiry = nil
            }
        } else if proAccessExpiry != nil {
            proAccessExpiry = nil
        }

        onChange?()
    }

    private func resolveRCPackage(for id: String) async throws -> Package? {
        // Prefer the cached offering; fall back to a fresh fetch.
        if let cached = try? await Purchases.shared.offerings().current {
            return cached.availablePackages.first(where: { $0.storeProduct.productIdentifier == id })
        }
        return nil
    }

    /// Enriches an already-mapped `SubscriptionOffering` with win-back offer
    /// eligibility for each package by asking RC per-package. Runs the
    /// per-package fetches concurrently since they're independent network
    /// calls. Failure to fetch a given package's offers is treated as "not
    /// eligible" — the paywall will just render the normal price.
    private static func attachingWinBackOffers(
        to offering: SubscriptionOffering?,
        from rcOffering: Offering
    ) async -> SubscriptionOffering? {
        guard var updated = offering else { return nil }
        async let monthlyOffer = winBackOfferInfo(forProductID: "pro_monthly", in: rcOffering)
        async let yearlyOffer  = winBackOfferInfo(forProductID: "pro_yearly",  in: rcOffering)
        // pro_lifetime is a non-consumable — Apple's win-back mechanism only
        // covers auto-renewing subs, so no need to query it.
        let (m, y) = await (monthlyOffer, yearlyOffer)
        if let m { updated.monthly?.winBackOffer = m }
        if let y { updated.yearly?.winBackOffer = y }
        return updated
    }

    private static func winBackOfferInfo(
        forProductID id: String,
        in rcOffering: Offering
    ) async -> WinBackOffer? {
        guard let package = rcOffering.availablePackages
            .first(where: { $0.storeProduct.productIdentifier == id }) else { return nil }
        let offers: [RevenueCat.WinBackOffer]
        do {
            offers = try await Purchases.shared.eligibleWinBackOffers(forPackage: package)
        } catch {
            return nil
        }
        guard let first = offers.first,
              let identifier = first.discount.offerIdentifier else { return nil }
        return WinBackOffer(
            identifier: identifier,
            priceString: first.discount.localizedPriceString,
            summary: winBackSummary(for: first.discount, basePackage: package)
        )
    }

    /// Resolves a specific eligible win-back offer by identifier so we can
    /// hand it back to RC at purchase time.
    private func eligibleWinBackOffer(
        for rcPackage: Package,
        matching identifier: String
    ) async throws -> RevenueCat.WinBackOffer? {
        let offers = try await Purchases.shared.eligibleWinBackOffers(forPackage: rcPackage)
        return offers.first { $0.discount.offerIdentifier == identifier }
    }

    /// Turns an SK2 promotional discount into the plain-language paywall
    /// summary. Reads mode + period + count and picks the cleanest phrasing.
    private static func winBackSummary(
        for discount: StoreProductDiscount,
        basePackage: Package
    ) -> String {
        let periodCount = discount.numberOfPeriods
        let periodName = periodString(discount.subscriptionPeriod.unit,
                                      count: discount.subscriptionPeriod.value * periodCount)
        switch discount.paymentMode {
        case .freeTrial:
            return "\(discount.subscriptionPeriod.value) \(periodName) free"
        case .payAsYouGo, .payUpFront:
            // Compute discount % vs base price for headline-style copy.
            let base = basePackage.storeProduct.price
            guard base > 0 else {
                return "\(discount.localizedPriceString) for \(periodCount) \(periodName)"
            }
            let saved = (base - discount.price) / base
            let pctNS = NSDecimalNumber(decimal: saved * Decimal(100))
            let pct = Int(pctNS.doubleValue.rounded())
            if pct >= 5 {
                return "\(pct)% off first \(periodName)"
            }
            return "\(discount.localizedPriceString) for first \(periodName)"
        }
    }

    private static func mapOfferings(_ offerings: Offerings) -> SubscriptionOffering? {
        guard let current = offerings.current else { return nil }

        let monthlyRC = current.availablePackages
            .first(where: { $0.storeProduct.productIdentifier == "pro_monthly" })
        let yearlyRC = current.availablePackages
            .first(where: { $0.storeProduct.productIdentifier == "pro_yearly" })
        let lifetimeRC = current.availablePackages
            .first(where: { $0.storeProduct.productIdentifier == "pro_lifetime" })

        let monthly = monthlyRC.map { package -> SubscriptionPackage in
            SubscriptionPackage(
                id: package.storeProduct.productIdentifier,
                priceString: package.storeProduct.localizedPriceString,
                periodString: "per month",
                introOfferString: introCopy(for: package, fallbackPeriod: "month"),
                introBadge: introBadge(for: package),
                savingsBadge: nil
            )
        }

        let yearly = yearlyRC.map { package -> SubscriptionPackage in
            SubscriptionPackage(
                id: package.storeProduct.productIdentifier,
                priceString: package.storeProduct.localizedPriceString,
                periodString: "per year",
                introOfferString: introCopy(for: package, fallbackPeriod: "year"),
                introBadge: introBadge(for: package),
                savingsBadge: nil
            )
        }

        // Lifetime is a non-consumable IAP — no subscription period, no intro
        // offer, no savings math against a shorter cadence. Just a price and a
        // "one-time" descriptor for the paywall.
        let lifetime = lifetimeRC.map { package -> SubscriptionPackage in
            SubscriptionPackage(
                id: package.storeProduct.productIdentifier,
                priceString: package.storeProduct.localizedPriceString,
                periodString: "one-time",
                introOfferString: nil,
                savingsBadge: nil
            )
        }

        return SubscriptionOffering(monthly: monthly, yearly: yearly, lifetime: lifetime)
    }

    /// Free-trial chip copy from the store intro period. Nil for paid intros.
    private static func introBadge(for package: Package) -> String? {
        guard let intro = package.storeProduct.introductoryDiscount,
              intro.paymentMode == .freeTrial else { return nil }
        let count = intro.subscriptionPeriod.value
        let unit = periodString(intro.subscriptionPeriod.unit, count: count)
        return "\(count) \(unit) free"
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

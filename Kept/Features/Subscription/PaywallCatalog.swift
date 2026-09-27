import Foundation

/// Plans the paywall is allowed to show. Monthly is intentionally absent:
/// Kept Pro is yearly (with its store intro offer) and lifetime.
enum PaywallPlan: String, Equatable, Hashable, CaseIterable {
    case yearly
    case lifetime
}

/// Which packages the paywall renders, and which one is selected by default.
/// Monthly is filtered out even when the current offering still includes it.
enum PaywallCatalog {
    /// Yearly first, then lifetime. Empty when neither package is present.
    /// A nil offering (still loading) is empty — the view shows placeholders.
    static func visiblePlans(in offering: SubscriptionOffering?) -> [PaywallPlan] {
        guard let offering else { return [] }
        var plans: [PaywallPlan] = []
        if offering.yearly != nil { plans.append(.yearly) }
        if offering.lifetime != nil { plans.append(.lifetime) }
        return plans
    }

    /// Yearly when it exists, otherwise lifetime, otherwise nothing to select.
    static func defaultSelection(in offering: SubscriptionOffering?) -> PaywallPlan? {
        let plans = visiblePlans(in: offering)
        if plans.contains(.yearly) { return .yearly }
        return plans.first
    }

    /// Keeps `preferred` when that plan is still on screen. Otherwise the default.
    static func resolvedSelection(
        _ preferred: PaywallPlan?,
        in offering: SubscriptionOffering?
    ) -> PaywallPlan? {
        let plans = visiblePlans(in: offering)
        if let preferred, plans.contains(preferred) { return preferred }
        return defaultSelection(in: offering)
    }

    static func package(
        _ plan: PaywallPlan,
        in offering: SubscriptionOffering?
    ) -> SubscriptionPackage? {
        switch plan {
        case .yearly: offering?.yearly
        case .lifetime: offering?.lifetime
        }
    }

    enum OfferState: Equatable {
        case loading
        case failed
        case ready
        case empty
    }

    /// Nil offering is still loading, unless the fetch already failed.
    /// A loaded offering with neither peer plan is empty, not a crash.
    static func offerState(offering: SubscriptionOffering?, loadFailed: Bool) -> OfferState {
        guard let offering else { return loadFailed ? .failed : .loading }
        return visiblePlans(in: offering).isEmpty ? .empty : .ready
    }

    static func hasIntroTrial(_ package: SubscriptionPackage?) -> Bool {
        guard let package, let count = package.introPeriodCount, count > 0 else { return false }
        return package.introPeriodUnit != nil
    }

    static func buttonTitle(plan: PaywallPlan, hasIntroTrial: Bool) -> String {
        switch plan {
        case .lifetime:
            return String(localized: "Buy Lifetime")
        case .yearly:
            return hasIntroTrial
                ? String(localized: "Start free trial")
                : String(localized: "Subscribe")
        }
    }

    /// N and the price come from the store package. The unit is the store
    /// intro period ("days", "week", …), not a fixed "7 days".
    static func yearlyTrialLine(count: Int, unit: String, price: String) -> String {
        String(localized: "Free for \(count) \(unit), then \(price)/year")
    }

    static func yearlyRenewalLine(price: String) -> String {
        String(localized: "Renews at \(price)/year. Cancel anytime in Settings.")
    }

    static func lifetimePriceLine(price: String) -> String {
        String(localized: "\(price) once")
    }
}

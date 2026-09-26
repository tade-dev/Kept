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
}

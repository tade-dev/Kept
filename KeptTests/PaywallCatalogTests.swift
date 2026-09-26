import Foundation
import Testing
@testable import Kept

@Suite("Paywall catalog")
struct PaywallCatalogTests {
    @Test("monthly is filtered out; yearly is the default when both peers exist")
    func filtersMonthlyAndDefaultsToYearly() {
        let offering = SubscriptionOffering(
            monthly: package("pro_monthly", price: "ignored"),
            yearly: package("pro_yearly", price: "from-store"),
            lifetime: package("pro_lifetime", price: "from-store")
        )

        #expect(PaywallCatalog.visiblePlans(in: offering) == [.yearly, .lifetime])
        #expect(PaywallCatalog.defaultSelection(in: offering) == .yearly)
        #expect(PaywallCatalog.package(.yearly, in: offering)?.id == "pro_yearly")
        #expect(PaywallCatalog.package(.lifetime, in: offering)?.id == "pro_lifetime")
    }

    @Test("a monthly-only offering shows nothing and selects nothing")
    func monthlyOnlyIsEmpty() {
        let offering = SubscriptionOffering(
            monthly: package("pro_monthly", price: "ignored", savings: "50% OFF"),
            yearly: nil,
            lifetime: nil
        )

        #expect(PaywallCatalog.visiblePlans(in: offering).isEmpty)
        #expect(PaywallCatalog.defaultSelection(in: offering) == nil)
    }

    @Test("missing yearly falls back to lifetime without crashing the selection")
    func lifetimeOnly() {
        let offering = SubscriptionOffering(
            monthly: package("pro_monthly", price: "ignored"),
            yearly: nil,
            lifetime: package("pro_lifetime", price: "from-store")
        )

        #expect(PaywallCatalog.visiblePlans(in: offering) == [.lifetime])
        #expect(PaywallCatalog.defaultSelection(in: offering) == .lifetime)
        #expect(PaywallCatalog.resolvedSelection(.yearly, in: offering) == .lifetime)
    }

    @Test("missing lifetime keeps yearly, including when the user had picked lifetime")
    func yearlyOnly() {
        let offering = SubscriptionOffering(
            monthly: nil,
            yearly: package("pro_yearly", price: "from-store"),
            lifetime: nil
        )

        #expect(PaywallCatalog.visiblePlans(in: offering) == [.yearly])
        #expect(PaywallCatalog.defaultSelection(in: offering) == .yearly)
        #expect(PaywallCatalog.resolvedSelection(.lifetime, in: offering) == .yearly)
    }

    @Test("an explicit lifetime choice sticks while lifetime is available")
    func lifetimeStaysSelected() {
        let offering = SubscriptionOffering(
            monthly: package("pro_monthly", price: "ignored"),
            yearly: package("pro_yearly", price: "from-store"),
            lifetime: package("pro_lifetime", price: "from-store")
        )

        #expect(PaywallCatalog.resolvedSelection(.lifetime, in: offering) == .lifetime)
        #expect(PaywallCatalog.resolvedSelection(nil, in: offering) == .yearly)
    }

    @Test("a missing offering has no plans")
    func nilOffering() {
        #expect(PaywallCatalog.visiblePlans(in: nil).isEmpty)
        #expect(PaywallCatalog.defaultSelection(in: nil) == nil)
        #expect(PaywallCatalog.resolvedSelection(.yearly, in: nil) == nil)
        #expect(PaywallCatalog.package(.yearly, in: nil) == nil)
    }

    private func package(_ id: String, price: String, savings: String? = nil) -> SubscriptionPackage {
        SubscriptionPackage(
            id: id,
            priceString: price,
            periodString: "period",
            introOfferString: nil,
            savingsBadge: savings
        )
    }
}

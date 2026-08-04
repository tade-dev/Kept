import Foundation
import SwiftData
import Testing
@testable import Kept

@Suite("Coverage logic")
struct CoverageLogicTests {
    @Test("refreshCoverage tracks the longest warranty")
    func refreshCoverageTracksLongest() throws {
        let purchase = Purchase(
            merchant: "Apple",
            itemName: "MacBook",
            price: 1999,
            currency: "USD",
            purchaseDate: date(2025, 1, 1)
        )

        let short = WarrantyTerm(
            durationMonths: 12,
            expiryDate: date(2026, 1, 1),
            source: .inferred,
            confidence: 0.7
        )
        let long = WarrantyTerm(
            durationMonths: 24,
            expiryDate: date(2027, 1, 1),
            source: .inferred,
            confidence: 0.7
        )
        purchase.warranties = [short, long]
        purchase.refreshCoverage()

        #expect(purchase.primaryWarranty?.durationMonths == 24)
        #expect(purchase.coverageEndsAt == date(2027, 1, 1))
    }

    @Test("setDuration refuses to overwrite a user-provided warranty with inference")
    func userEditsWin() throws {
        let purchase = Purchase(
            merchant: "Currys",
            itemName: "TV",
            price: 429,
            currency: "GBP",
            purchaseDate: date(2025, 4, 22)
        )

        #expect(purchase.setDuration(months: 24, byUser: true))
        #expect(purchase.primaryWarranty?.source == .userProvided)
        #expect(purchase.coverageEndsAt == date(2027, 4, 22))

        #expect(purchase.setDuration(months: 12, byUser: false) == false)
        #expect(purchase.primaryWarranty?.durationMonths == 24)
        #expect(purchase.primaryWarranty?.source == .userProvided)
    }

    @Test("setDuration allows the user to overwrite an inferred warranty")
    func userCanOverrideInference() throws {
        let purchase = Purchase(
            merchant: "Best Buy",
            itemName: "Headphones",
            price: 348,
            currency: "USD",
            purchaseDate: date(2025, 1, 15)
        )

        #expect(purchase.setDuration(months: 12, byUser: false))
        #expect(purchase.primaryWarranty?.source == .inferred)

        #expect(purchase.setDuration(months: 36, byUser: true))
        #expect(purchase.primaryWarranty?.durationMonths == 36)
        #expect(purchase.primaryWarranty?.source == .userProvided)
        #expect(purchase.coverageEndsAt == date(2028, 1, 15))
    }

    @Test("clearing duration removes a non-user warranty")
    func clearingRemovesInferred() throws {
        let purchase = Purchase(merchant: "Target", itemName: "Instant Pot", price: 99.99)
        #expect(purchase.setDuration(months: 12, byUser: false))
        #expect(purchase.setDuration(months: 0, byUser: false))
        #expect(purchase.primaryWarranty == nil)
        #expect(purchase.coverageEndsAt == nil)
    }

    @Test("legacy userSet raw value maps to userProvided")
    func legacySourceMaps() {
        let term = WarrantyTerm()
        term.sourceRaw = "userSet"
        #expect(term.source == .userProvided)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}

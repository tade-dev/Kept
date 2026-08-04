import Foundation
import Testing
@testable import Kept

@Suite("ModelExtractor.merge")
struct ModelExtractorMergeTests {
    @Test("rules keep price and date; model fills item, warranty, and return window")
    func mergePrefersRulesMoney() {
        let rules = ExtractedReceipt(
            merchant: "APPLE STORE",
            itemName: "",
            price: 2849,
            currency: "AUD",
            purchaseDate: "2024-11-26",
            warrantyDurationMonths: 0,
            warrantyIsInferred: false,
            returnWindowDays: 14,
            returnWindowIsInferred: true,
            confidence: 0.7
        )
        let model = ExtractedReceipt(
            merchant: "Apple Store",
            itemName: "iPhone 16 Pro Max 1TB",
            price: 99,
            currency: "USD",
            purchaseDate: "2026-01-01",
            warrantyDurationMonths: 12,
            warrantyIsInferred: true,
            returnWindowDays: 14,
            returnWindowIsInferred: true,
            confidence: 0.9
        )

        let merged = ModelExtractor.merge(rules: rules, model: model)
        #expect(merged.merchant == "Apple Store")
        #expect(merged.itemName == "iPhone 16 Pro Max 1TB")
        #expect(merged.price == 2849)
        #expect(merged.currency == "AUD")
        #expect(merged.purchaseDate == "2024-11-26")
        #expect(merged.warrantyDurationMonths == 12)
        #expect(merged.warrantyIsInferred == true)
        #expect(merged.returnWindowDays == 14)
    }

    @Test("fashion keeps return window and zero warranty from model")
    func fashionReturnOnly() {
        let rules = ExtractedReceipt(
            merchant: "Primark Stores Ltd",
            itemName: "CARGO NAVY",
            price: 22,
            currency: "GBP",
            purchaseDate: "2024-03-07",
            warrantyDurationMonths: 0,
            warrantyIsInferred: false,
            returnWindowDays: 28,
            returnWindowIsInferred: true,
            confidence: 0.6
        )
        let model = ExtractedReceipt(
            merchant: "Primark",
            itemName: "Cargo navy",
            price: 22,
            currency: "GBP",
            purchaseDate: "2024-03-07",
            warrantyDurationMonths: 0,
            warrantyIsInferred: false,
            returnWindowDays: 28,
            returnWindowIsInferred: true,
            confidence: 0.85
        )

        let merged = ModelExtractor.merge(rules: rules, model: model)
        #expect(merged.warrantyDurationMonths == 0)
        #expect(merged.returnWindowDays == 28)
        #expect(merged.itemName == "Cargo navy")
    }
}

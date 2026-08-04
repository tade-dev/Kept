import CoreGraphics
import Foundation
import Testing
@testable import Kept

@Suite("RulesExtractor")
struct RulesExtractorTests {
    private let extractor = RulesExtractor()

    @Test("extracts Apple Store AUD total and date")
    func appleStore() {
        let lines = makeLines([
            "APPLE STORE",
            "Chermside QLD",
            "iPhone 16 Pro Max 1TB",
            "26/11/2024",
            "TOTAL A$2,849.00",
        ])
        let result = extractor.extract(from: lines)
        #expect(result.merchant == "APPLE STORE")
        #expect(result.price == 2849)
        #expect(result.currency == "AUD")
        #expect(result.purchaseDate == "2024-11-26")
        #expect(result.warrantyDurationMonths == 0)
    }

    @Test("extracts Primark GBP total")
    func primark() {
        let lines = makeLines([
            "Primark Stores Ltd",
            "4169504 CARGO NAVY",
            "07/03/2024",
            "TOTAL £22.00",
        ])
        let result = extractor.extract(from: lines)
        #expect(result.merchant == "Primark Stores Ltd")
        #expect(result.price == 22)
        #expect(result.currency == "GBP")
        #expect(result.itemName == "CARGO NAVY")
        #expect(result.purchaseDate == "2024-03-07")
    }

    @Test("prefers labeled TOTAL over larger line items")
    func prefersLabeledTotal() {
        let lines = makeLines([
            "Best Buy",
            "Sony WH-1000XM5",
            "348.00",
            "Accessory 12.00",
            "TOTAL $360.00",
        ])
        let result = extractor.extract(from: lines)
        #expect(result.price == 360)
        #expect(result.currency == "USD")
    }

    @Test("ISO date parses as written")
    func isoDate() {
        let lines = makeLines([
            "Target",
            "Instant Pot Duo",
            "2025-03-30",
            "TOTAL $99.99",
        ])
        let result = extractor.extract(from: lines)
        #expect(result.purchaseDate == "2025-03-30")
        #expect(result.price == 99.99)
    }

    private func makeLines(_ texts: [String]) -> [RecognizedLine] {
        texts.enumerated().map { index, text in
            RecognizedLine(
                text: text,
                confidence: 0.95,
                boundingBox: CGRect(x: 0, y: 1 - Double(index) * 0.08, width: 1, height: 0.05)
            )
        }
    }
}

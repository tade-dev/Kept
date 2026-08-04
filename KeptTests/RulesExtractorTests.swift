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

    @Test("extracts Primark GBP total and infers return window")
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
        #expect(result.warrantyDurationMonths == 0)
        #expect(result.returnWindowDays == 28)
        #expect(result.returnWindowIsInferred == true)
    }

    @Test("uses printed last-day-for-refund date instead of guessing")
    func explicitRefundDeadline() {
        let lines = makeLines([
            "Grays",
            "PRIMARK STORES LTD",
            "4169504 CARGO NAVY",
            "Date: 07/03/20 Time: 15:32",
            "TOTAL 22.00",
            "Last day for refund or exchange 04/04/2020",
            "THANK YOU",
            "Reading Berkshire",
        ])
        let result = extractor.extract(from: lines)
        #expect(result.merchant.uppercased().contains("PRIMARK"))
        #expect(result.price == 22)
        #expect(result.currency == "GBP")
        #expect(result.purchaseDate == "2020-03-07")
        // 7 Mar → 4 Apr 2020 = 28 days, and not inferred
        #expect(result.returnWindowDays == 28)
        #expect(result.returnWindowIsInferred == false)
        #expect(result.warrantyDurationMonths == 0)
    }

    @Test("groceries get no return window from rules floor")
    func groceryNoReturn() {
        let lines = makeLines([
            "Woolworths",
            "Tax Invoice",
            "03/02/2025",
            "TOTAL A$15.98",
        ])
        let result = extractor.extract(from: lines)
        #expect(result.returnWindowDays == 0)
        #expect(result.warrantyDurationMonths == 0)
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

    @Test("parses Apple AU written month date and full dollar total")
    func appleChermsideWrittenDate() {
        let lines = makeLines([
            "Apple Chermside",
            "Westfield Chermside QLD 4032",
            "https://www.apple.com/au/retail/chermside/",
            "26 November 2024 14:24",
            "IPHONE 16 PRO MAX 1TB Desert Titanium",
            "$ 2,521.20",
            "Sub-Total $ 2,521.20",
            "GST/HST $ 327.80",
            "Total $ 2,849.00",
        ])
        let result = extractor.extract(from: lines)
        #expect(result.merchant.contains("Apple"))
        #expect(result.purchaseDate == "2024-11-26")
        #expect(result.price == 2849)
        #expect(result.currency == "AUD")
    }

    @Test("does not collapse OCR 2.849.00 into 2.85")
    func mangledThousandsSeparators() {
        let lines = makeLines([
            "Apple Chermside",
            "QLD Australia",
            "28 November 2024 16:24",
            "Total $ 2.849.00",
        ])
        let result = extractor.extract(from: lines)
        #expect(result.price == 2849)
        #expect(result.purchaseDate == "2024-11-28")
        #expect(result.currency == "AUD")
    }

    @Test("ignores IMEI digits pretending to be a price")
    func ignoresIMEIBleed() {
        let lines = makeLines([
            "Apple Chermside",
            "Westfield Chermside QLD 4032",
            "26 November 2024 14:24",
            "IPHONE 16 PRO MAX 1TB Desert Titanium",
            "$ 2,521.20",
            "Part: MYX63X/A",
            "Serial No. LLJYY26L3K",
            "IMEI 1 350108727082833",
            "IMEI 2 350108725734039",
            // Vision sometimes inserts dots into long digit runs
            "IMEI 1 350.108727082833",
            "Sub-Total $ 2,521.20",
            "GST/HST $ 327.80",
            "Total $ 2,849.00",
            "Paid Visa commonwealth banking $ 2,849.00",
            "5195726651",
        ])
        let result = extractor.extract(from: lines)
        #expect(result.price == 2849)
        #expect(result.currency == "AUD")
    }

    @Test("recovers Total when OCR drops the decimal point")
    func recoversDroppedDecimalOnTotal() {
        let lines = makeLines([
            "Apple Chermside",
            "QLD 4032",
            "26 November 2024 14:24",
            "IMEI 1 350.118727082833",
            "Total $ 284900",
        ])
        let result = extractor.extract(from: lines)
        #expect(result.price == 2849)
        #expect(result.currency == "AUD")
    }

    @Test("ignores Visa auth codes even when Total OCR is weak")
    func ignoresAuthCode() {
        let lines = makeLines([
            "Apple Chermside",
            "QLD 4032",
            "26 November 2024 14:24",
            "IPHONE 16 PRO MAX 1TB Desert Titanium",
            "$ 2,521.20",
            "Sub-Total $ 2,521.20",
            "GST/HST $ 327.80",
            // Total line missing / unread — Paid still carries the amount
            "Paid Visa commonwealth banking $ 2,849.00",
            "(Chip) **** 1006",
            "Auth: 860515",
            "Please debit my account ****1006 by $2,849.00(Sale)",
            "APPROVED",
            "5195726651",
        ])
        let result = extractor.extract(from: lines)
        #expect(result.price == 2849)
        #expect(result.currency == "AUD")
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

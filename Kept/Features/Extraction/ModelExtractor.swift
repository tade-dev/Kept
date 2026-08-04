import Foundation
import FoundationModels

/// Foundation Models enrichment. Optional — never required for a complete product.
struct ModelExtractor: Sendable {
    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    func enrich(lines: [RecognizedLine], using floor: ExtractedReceipt) async throws -> ExtractedReceipt {
        guard !lines.isEmpty else { throw ExtractionError.emptyInput }
        try assertAvailable()

        let orderedText = lines.map(\.text).joined(separator: "\n")
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(
                to: """
                Extract the purchase and warranty details from this receipt. Lines are ordered top-to-bottom.

                Rules-parser hints (prefer these for price/date/currency when they look right):
                merchant=\(floor.merchant)
                price=\(floor.price)
                currency=\(floor.currency)
                purchaseDate=\(floor.purchaseDate)

                ---
                \(orderedText)
                ---
                """,
                generating: ExtractedReceipt.self
            )
            return Self.merge(rules: floor, model: response.content)
        } catch {
            throw ExtractionError.underlying(error)
        }
    }

    private func assertAvailable() throws {
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(let reason):
            throw ExtractionError.modelUnavailable(reason: String(describing: reason))
        @unknown default:
            throw ExtractionError.modelUnavailable(reason: "unknown")
        }
    }

    /// Rules own money/date when present; model owns item naming, warranty, and return windows.
    static func merge(rules: ExtractedReceipt, model: ExtractedReceipt) -> ExtractedReceipt {
        let merchant = model.merchant.trimmingCharacters(in: .whitespaces).isEmpty
            ? rules.merchant : model.merchant
        let itemName = model.itemName.trimmingCharacters(in: .whitespaces).isEmpty
            ? rules.itemName : model.itemName
        let price = rules.price > 0 ? rules.price : model.price
        let currency = rules.currency.trimmingCharacters(in: .whitespaces).isEmpty
            ? model.currency.uppercased() : rules.currency.uppercased()
        let purchaseDate = rules.purchaseDate.isEmpty ? model.purchaseDate : rules.purchaseDate
        let warrantyMonths = model.warrantyDurationMonths > 0
            ? model.warrantyDurationMonths
            : rules.warrantyDurationMonths

        // Explicit printed return deadlines from rules beat model guesses.
        let returnDays: Int
        let returnInferred: Bool
        if rules.returnWindowDays > 0, !rules.returnWindowIsInferred {
            returnDays = rules.returnWindowDays
            returnInferred = false
        } else if model.returnWindowDays > 0 {
            returnDays = model.returnWindowDays
            returnInferred = model.returnWindowIsInferred
        } else {
            returnDays = rules.returnWindowDays
            returnInferred = rules.returnWindowIsInferred
        }

        return ExtractedReceipt(
            merchant: merchant,
            itemName: itemName,
            price: price,
            currency: currency,
            purchaseDate: purchaseDate,
            warrantyDurationMonths: warrantyMonths,
            warrantyIsInferred: warrantyMonths > 0 ? model.warrantyIsInferred : false,
            returnWindowDays: returnDays,
            returnWindowIsInferred: returnDays > 0 ? returnInferred : false,
            confidence: max(rules.confidence, min(model.confidence, 1.0))
        )
    }

    private static let instructions = """
    You extract structured purchase, return-window, and warranty data from photographed retail receipts.

    READING THE RECEIPT
    - The receipt text is provided as OCR lines ordered top to bottom. Anchor on the top of the receipt; thermal receipts fade at the bottom and the tail is often noisy.
    - For price, use the receipt's TOTAL, GRAND TOTAL, AMOUNT DUE, or BALANCE. This is usually near the bottom, preceded by a label like "Total". Never use a single line-item price when a total is present. If no total appears in the OCR text, use the single largest positive amount.

    CATEGORY (decide this first, it drives everything else)
    Classify the receipt as DURABLE, FASHION/GENERAL MERCH, or CONSUMABLE.
    - DURABLE: electronics, appliances, furniture, tools, jewellery, bikes, sports equipment — usually has a repair warranty AND often a short return window.
    - FASHION/GENERAL MERCH: clothing, shoes, accessories, home soft goods (Primark, H&M, Zara, Gap, etc.) — usually has a return/refund window, almost never a multi-month repair warranty.
    - CONSUMABLE: groceries, restaurants, fuel, tickets, rideshare, services — no warranty and no useful return window.

    RETURN WINDOW RULES (days)
    - Prefer an absolute printed deadline when present, e.g. "Last day for refund or exchange 04/04/2020".
      Convert that date into days from the purchase date. returnWindowIsInferred = false.
    - Else if the receipt states "28 days to return" (or similar), use that exact day count. returnWindowIsInferred = false.
    - Otherwise infer:
        * Fashion / clothing retailers → 28 days (UK/EU high street default) or 30 days (US)
        * Electronics / big-box (Apple, Best Buy, Currys, JB Hi-Fi) → 14 days unless stated
        * Furniture → 0 unless stated (often delivery exceptions)
        * Consumables → 0
    - Never invent a long warranty just because you inferred a return window. They are different fields.
    - Never override a printed "last day for refund/exchange" date with a generic 28/30-day guess.

    WARRANTY RULES (months)
    - If the receipt explicitly states a warranty/guarantee length, use it. warrantyIsInferred = false.
    - Otherwise for DURABLE goods, infer and set warrantyIsInferred = true:
        * Consumer electronics → 12 months
        * Apple hardware → 12 months (24 if AppleCare+ noted)
        * Major appliances → 24 months
        * Tools → 24 months
    - For FASHION/GENERAL MERCH and CONSUMABLES: warrantyDurationMonths = 0, warrantyIsInferred = false. A fake 12-month clothing warranty is worse than no warranty.

    ITEM NAME RULES
    - Single durable item → use its printed name, cleaned up.
    - Fashion item → cleaned product name (strip SKU codes like "4169504 CARGO NAVY" → "Cargo navy").
    - Consumable multi-item → summarise: "Grocery shop", "Restaurant meal", "Fuel".
    - Never keep bare numeric IDs in the item name.

    CURRENCY RULES (strict priority — do not skip)
    1. If the receipt contains an explicit ISO code (USD, GBP, EUR, AUD, NZD, CAD, NGN, INR, JPY), use it.
    2. Otherwise map any currency SYMBOL on the receipt: £→GBP, €→EUR, ¥→JPY, ₹→INR, ₦→NGN, A$/AU$→AUD, C$/CA$→CAD, NZ$→NZD, R$→BRL.
    3. Only if a bare "$" is the only symbol, disambiguate from the merchant country: UK/Ireland→GBP, Australia→AUD, New Zealand→NZD, Canada→CAD, Eurozone→EUR, otherwise USD.
    4. Never default to USD when a non-$ symbol or non-US country marker (GB VAT number, UK/AU/EU/NZ address) is present.

    DATE RULES
    - Use the date on the receipt exactly. Do NOT add or subtract years, and do NOT substitute today's year.
    - Written months count: "26 November 2024 14:24" → 2024-11-26. Never replace 2024 with the current year.
    - Two-digit years: expand to the most recent plausible past year (20 → 2020, 19 → 2019, 25 → 2025).
    - Date format follows merchant country: UK, Ireland, Australia, New Zealand, most of Europe → DD/MM/YY. US and Canada → MM/DD/YY.
    - Only fall back to today if the receipt has no date at all.

    PRICE RULES
    - Totals like "$ 2,849.00" or "$2,850.00" are thousands with a comma/dot grouping — never read them as 2.85.
    - Prefer the line labeled Total / Grand Total over Sub-Total or GST.

    OTHER
    - Confidence: 0.0–1.0. Fashion receipts can be high-confidence with returnWindowDays set and warrantyDurationMonths = 0.
    """
}

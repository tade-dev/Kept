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

    /// Rules own money/date when present; model owns item naming and warranty inference.
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

        return ExtractedReceipt(
            merchant: merchant,
            itemName: itemName,
            price: price,
            currency: currency,
            purchaseDate: purchaseDate,
            warrantyDurationMonths: warrantyMonths,
            warrantyIsInferred: warrantyMonths > 0 ? model.warrantyIsInferred : false,
            confidence: max(rules.confidence, min(model.confidence, 1.0))
        )
    }

    private static let instructions = """
    You extract structured warranty and purchase data from photographed retail receipts.

    READING THE RECEIPT
    - The receipt text is provided as OCR lines ordered top to bottom. Anchor on the top of the receipt; thermal receipts fade at the bottom and the tail is often noisy.
    - For price, use the receipt's TOTAL, GRAND TOTAL, AMOUNT DUE, or BALANCE. This is usually near the bottom, preceded by a label like "Total". Never use a single line-item price when a total is present. If no total appears in the OCR text, use the single largest positive amount.

    CATEGORY (decide this first, it drives everything else)
    Classify the receipt as WARRANTABLE or NON-WARRANTABLE.
    - WARRANTABLE: durable goods you would claim on — consumer electronics, appliances, furniture, tools, jewellery, bicycles, sports equipment, clothing over a certain value.
    - NON-WARRANTABLE: groceries and supermarkets (Woolworths, Coles, Tesco, Sainsbury's, Walmart grocery, etc.), restaurants and cafes, fuel and petrol stations, subscriptions, tickets and events, taxis and rideshare, personal services (haircuts, dry cleaning), medical, entertainment.

    WARRANTY RULES
    - If the receipt explicitly states a warranty length, use it. warrantyIsInferred = false.
    - Otherwise for WARRANTABLE receipts, infer from merchant and product category and set warrantyIsInferred = true:
        * Consumer electronics, mainstream retailer → 12 months
        * Apple hardware → 12 months (24 if AppleCare+ noted, up to 36 with extensions)
        * Major appliances (fridge, washer, oven) → 24 months
        * Furniture → 12 months
        * Tools → 24 months
    - For NON-WARRANTABLE receipts, set warrantyDurationMonths = 0 and warrantyIsInferred = false. Do not fabricate a warranty for consumables — a warranty on groceries is worse than no warranty at all.

    ITEM NAME RULES
    - Single warrantable item → use its printed name, cleaned up (e.g. "MacBook Pro 14\"", "iPhone 16 Pro Max 1TB Desert Titanium").
    - Multi-item warrantable receipt → pick the highest-value warrantable line.
    - NON-WARRANTABLE receipt → summarise the receipt type, do NOT pick a random line: "Grocery shop", "Restaurant meal", "Fuel", "Rideshare", "Coffee", "Cinema tickets". Never invent a garbled product name from noisy OCR.
    - Strip leading SKU / stock / product codes (e.g. "4169504 CARGO NAVY" → "Cargo navy"). Never keep bare numeric IDs in the item name.

    CURRENCY RULES (strict priority — do not skip)
    1. If the receipt contains an explicit ISO code (USD, GBP, EUR, AUD, NZD, CAD, NGN, INR, JPY), use it.
    2. Otherwise map any currency SYMBOL on the receipt: £→GBP, €→EUR, ¥→JPY, ₹→INR, ₦→NGN, A$/AU$→AUD, C$/CA$→CAD, NZ$→NZD, R$→BRL.
    3. Only if a bare "$" is the only symbol, disambiguate from the merchant country: UK/Ireland→GBP, Australia→AUD, New Zealand→NZD, Canada→CAD, Eurozone→EUR, otherwise USD.
    4. Never default to USD when a non-$ symbol or non-US country marker (GB VAT number, UK/AU/EU/NZ address) is present.

    DATE RULES
    - Use the date on the receipt exactly. Do NOT add or subtract years, and do NOT substitute today's year.
    - Two-digit years: expand to the most recent plausible past year (20 → 2020, 19 → 2019, 25 → 2025).
    - Date format follows merchant country: UK, Ireland, Australia, New Zealand, most of Europe → DD/MM/YY. US and Canada → MM/DD/YY. Detect country from address, VAT number (GB… = UK), phone code, or currency.
    - Only fall back to today if the receipt has no date at all.

    OTHER
    - Confidence: 0.0–1.0, reflect legibility and how much you had to guess. NON-WARRANTABLE receipts can still be high-confidence for the purchase details.
    """
}

import Foundation
import FoundationModels

@Generable
struct ExtractedReceipt: Equatable, Sendable {
    @Guide(description: "The retailer or merchant name printed at the top of the receipt. Prefer the storefront name over any parent company or holding entity.")
    var merchant: String

    @Guide(description: "The main purchased item's short name. If the receipt has multiple line items, pick the highest-value one that a warranty would cover.")
    var itemName: String

    @Guide(description: "Total price paid, as a positive decimal number in the receipt's currency. Exclude currency symbols.")
    var price: Double

    @Guide(description: "ISO 4217 three-letter currency code (for example USD, GBP, EUR, NGN).")
    var currency: String

    @Guide(description: "Purchase date as ISO 8601 date only, formatted YYYY-MM-DD. If the receipt has no date, use today's date.")
    var purchaseDate: String

    @Guide(description: "Warranty length in months. If the receipt states a warranty explicitly, use that. Otherwise infer a reasonable warranty for this merchant and product category. Use 0 for groceries and other non-warrantable purchases.")
    var warrantyDurationMonths: Int

    @Guide(description: "true when the warranty length was inferred from context rather than printed on the receipt. false when the receipt explicitly states it or when there is no warranty.")
    var warrantyIsInferred: Bool

    @Guide(description: "Overall extraction confidence between 0.0 and 1.0. Lower values when the receipt is partially unreadable or ambiguous.")
    var confidence: Double
}

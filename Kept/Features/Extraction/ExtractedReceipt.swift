import Foundation
import FoundationModels

@Generable
struct ExtractedReceipt: Equatable, Sendable {
    @Guide(description: "The retailer or merchant name printed at the top of the receipt. Prefer the storefront name over any parent company or holding entity.")
    var merchant: String

    @Guide(description: "The main purchased item's short name. If the receipt has multiple line items, pick the highest-value one that a warranty would cover. For clothing or multi-item fashion receipts, use a cleaned product name. For groceries, summarise as Grocery shop.")
    var itemName: String

    @Guide(description: "Total price paid, as a positive decimal number in the receipt's currency. Exclude currency symbols.")
    var price: Double

    @Guide(description: "ISO 4217 three-letter currency code (for example USD, GBP, EUR, NGN).")
    var currency: String

    @Guide(description: "Purchase date as ISO 8601 date only, formatted YYYY-MM-DD. If the receipt has no date, use today's date.")
    var purchaseDate: String

    @Guide(description: "Manufacturer or retailer warranty length in months. Use 0 for clothing, groceries, and other purchases with no real repair warranty. Prefer an explicit warranty/guarantee printed on the receipt.")
    var warrantyDurationMonths: Int

    @Guide(description: "true when the warranty length was inferred rather than printed. false when explicit or when warrantyDurationMonths is 0.")
    var warrantyIsInferred: Bool

    @Guide(description: "Retailer return or refund window in days (for example 14, 28, 30). Clothing and general merchandise usually have a return window even with no warranty. Use 0 for groceries, restaurants, fuel, and other non-returnable purchases, or when no return policy applies.")
    var returnWindowDays: Int

    @Guide(description: "true when the return window was inferred from merchant/category rather than printed. false when the receipt states it or when returnWindowDays is 0.")
    var returnWindowIsInferred: Bool

    @Guide(description: "Overall extraction confidence between 0.0 and 1.0. Lower values when the receipt is partially unreadable or ambiguous.")
    var confidence: Double
}

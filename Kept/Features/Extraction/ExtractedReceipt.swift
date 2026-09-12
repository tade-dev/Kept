import Foundation

/// Canonical receipt payload used across the app. Kept as a plain Swift
/// struct so it can be constructed on any iOS version — the Foundation
/// Models `@Generable` mirror lives inside `ModelExtractor` (iOS 26+) and
/// maps into this type after generation.
struct ExtractedReceipt: Equatable, Sendable {
    var merchant: String
    var itemName: String
    /// Bucket label ("Groceries", "Fashion", "Repair", …). Empty when the
    /// cloud path didn't return one — UI callers fall back to itemName.
    var category: String = ""
    var price: Double
    var currency: String
    var purchaseDate: String
    var warrantyDurationMonths: Int
    var warrantyIsInferred: Bool
    var returnWindowDays: Int
    var returnWindowIsInferred: Bool
    var confidence: Double
}

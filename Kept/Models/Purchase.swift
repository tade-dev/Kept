import Foundation
import SwiftData

@Model
final class Purchase {
    var merchant: String = ""
    var itemName: String = ""
    var price: Decimal = 0
    var currency: String = "USD"
    var purchaseDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    var notes: String = ""
    @Attribute(.externalStorage) var receiptImage: Data?
    var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)

    /// Denormalised end of the longest warranty. Kept queryable for `#Predicate`.
    private(set) var coverageEndsAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \WarrantyTerm.purchase)
    var warranties: [WarrantyTerm]?

    @Relationship(deleteRule: .cascade, inverse: \PassRecord.purchase)
    var passRecords: [PassRecord]?

    init(
        merchant: String = "",
        itemName: String = "",
        price: Decimal = 0,
        currency: String = Locale.current.currency?.identifier ?? "USD",
        purchaseDate: Date = .now,
        notes: String = "",
        receiptImage: Data? = nil
    ) {
        self.merchant = merchant
        self.itemName = itemName
        self.price = price
        self.currency = currency
        self.purchaseDate = purchaseDate
        self.notes = notes
        self.receiptImage = receiptImage
        self.createdAt = .now
        self.warranties = []
        self.passRecords = []
    }

    /// Longest-running warranty term, if any.
    var primaryWarranty: WarrantyTerm? {
        (warranties ?? []).max(by: { $0.expiryDate < $1.expiryDate })
    }

    func refreshCoverage() {
        coverageEndsAt = primaryWarranty?.expiryDate
    }

    /// Sets or updates the primary warranty duration.
    /// User-provided values are never overwritten by inferred extraction.
    @discardableResult
    func setDuration(months: Int, byUser: Bool) -> Bool {
        if months <= 0 {
            guard let existing = primaryWarranty else {
                refreshCoverage()
                return true
            }
            if existing.source == .userProvided && !byUser {
                return false
            }
            if var list = warranties, let index = list.firstIndex(where: { $0 === existing }) {
                list.remove(at: index)
                warranties = list
            }
            refreshCoverage()
            return true
        }

        let expiry = Calendar.current.date(
            byAdding: .month,
            value: months,
            to: purchaseDate
        ) ?? purchaseDate

        if let existing = primaryWarranty {
            if existing.source == .userProvided && !byUser {
                return false
            }
            existing.durationMonths = months
            existing.expiryDate = expiry
            if byUser {
                existing.source = .userProvided
                existing.confidence = 1.0
            }
        } else {
            let term = WarrantyTerm(
                durationMonths: months,
                expiryDate: expiry,
                source: byUser ? .userProvided : .inferred,
                confidence: byUser ? 1.0 : 0.7
            )
            if warranties == nil { warranties = [] }
            warranties?.append(term)
        }

        refreshCoverage()
        return true
    }
}

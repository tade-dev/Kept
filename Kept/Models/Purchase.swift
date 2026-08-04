import Foundation
import SwiftData

@Model
final class Purchase {
    var merchant: String
    var itemName: String
    var price: Decimal
    var currency: String
    var purchaseDate: Date
    var notes: String
    @Attribute(.externalStorage) var receiptImage: Data?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \WarrantyTerm.purchase)
    var warranty: WarrantyTerm?

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
    }
}

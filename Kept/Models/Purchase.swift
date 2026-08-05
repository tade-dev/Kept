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
    var ocrLinesData: Data?
    var lineItemsData: Data?
    var needsReextraction: Bool = false
    var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)

    var lineItems: [ReceiptLineItem] {
        get { ReceiptLineItem.decodeList(lineItemsData) }
        set { lineItemsData = ReceiptLineItem.encodeList(newValue) }
    }

    /// Denormalised end of the longest coverage term. Kept queryable for `#Predicate`.
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
        receiptImage: Data? = nil,
        ocrLinesData: Data? = nil,
        lineItemsData: Data? = nil,
        needsReextraction: Bool = false
    ) {
        self.merchant = merchant
        self.itemName = itemName
        self.price = price
        self.currency = currency
        self.purchaseDate = purchaseDate
        self.notes = notes
        self.receiptImage = receiptImage
        self.ocrLinesData = ocrLinesData
        self.lineItemsData = lineItemsData
        self.needsReextraction = needsReextraction
        self.createdAt = .now
        self.warranties = []
        self.passRecords = []
    }

    private var terms: [WarrantyTerm] {
        warranties ?? []
    }

    /// Longest-running manufacturer/retailer warranty (excludes return windows).
    var primaryWarranty: WarrantyTerm? {
        terms
            .filter { $0.kind == .warranty }
            .max(by: { $0.expiryDate < $1.expiryDate })
    }

    /// Retailer return window, if any.
    var returnWindow: WarrantyTerm? {
        terms.first(where: { $0.kind == .returnWindow })
    }

    /// Soonest actionable deadline for badges — active return/warranty first, else most recent expiry.
    var nextDeadline: WarrantyTerm? {
        let now = Date.now
        let upcoming = terms
            .filter { $0.expiryDate >= now }
            .sorted { $0.expiryDate < $1.expiryDate }
        if let next = upcoming.first { return next }
        return terms.max(by: { $0.expiryDate < $1.expiryDate })
    }

    func refreshCoverage() {
        coverageEndsAt = terms.map(\.expiryDate).max()
    }

    /// Sets or updates the warranty term. Never overwrites a user-provided value with inference.
    @discardableResult
    func setDuration(months: Int, byUser: Bool) -> Bool {
        mutateTerm(
            kind: .warranty,
            clear: months <= 0,
            byUser: byUser
        ) { term in
            let expiry = Calendar.current.date(
                byAdding: .month,
                value: months,
                to: purchaseDate
            ) ?? purchaseDate
            term.durationMonths = months
            term.durationDays = 0
            term.expiryDate = expiry
            term.kind = .warranty
        }
    }

    /// Sets or updates the return window (day-based). User edits always win.
    @discardableResult
    func setReturnWindow(days: Int, byUser: Bool) -> Bool {
        mutateTerm(
            kind: .returnWindow,
            clear: days <= 0,
            byUser: byUser
        ) { term in
            let expiry = Calendar.current.date(
                byAdding: .day,
                value: days,
                to: purchaseDate
            ) ?? purchaseDate
            term.durationDays = days
            term.durationMonths = 0
            term.expiryDate = expiry
            term.kind = .returnWindow
        }
    }

    private func mutateTerm(
        kind: CoverageKind,
        clear: Bool,
        byUser: Bool,
        update: (WarrantyTerm) -> Void
    ) -> Bool {
        let existing = terms.first(where: { $0.kind == kind })

        if clear {
            guard let existing else {
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

        if let existing {
            if existing.source == .userProvided && !byUser {
                return false
            }
            update(existing)
            if byUser {
                existing.source = .userProvided
                existing.confidence = 1.0
            }
        } else {
            let term = WarrantyTerm(
                source: byUser ? .userProvided : .inferred,
                kind: kind,
                confidence: byUser ? 1.0 : 0.7
            )
            update(term)
            if warranties == nil { warranties = [] }
            warranties?.append(term)
        }

        refreshCoverage()
        return true
    }
}

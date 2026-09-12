import Foundation

/// Per-field extraction result for the confirm screen. Any field may be nil
/// when the extractor declined to guess — nil is a first-class signal, not
/// an error. Confidence is 0...1 or nil when the value is nil.
nonisolated struct ReceiptExtraction: Equatable, Sendable {
    nonisolated struct Field<T: Equatable & Sendable>: Equatable, Sendable {
        var value: T? = nil
        var confidence: Double? = nil
    }

    var itemName: Field<String>
    var merchant: Field<String>
    var total: Field<Decimal>
    var currency: Field<String>
    var purchaseDate: Field<Date>
    var coverage: Field<CoverageEstimate>
    /// Semantic bucket ("Groceries", "Fashion", "Repair", …) surfaced as
    /// the receipt's subtitle in Library + Review. Empty when unknown.
    var category: String = ""
    /// Line items extracted from the receipt. Empty when the receipt has
    /// no itemised rows or the extractor couldn't read them.
    var lineItems: [ReceiptLineItem] = []

    static let empty = ReceiptExtraction(
        itemName: Field(),
        merchant: Field(),
        total: Field(),
        currency: Field(),
        purchaseDate: Field(),
        coverage: Field(),
        category: "",
        lineItems: []
    )
}

/// One coverage term. `isInferred` == true means the duration was guessed
/// rather than printed — always caption as "Estimated" until the user edits.
nonisolated struct CoverageEstimate: Equatable, Sendable {
    var kind: CoverageKind
    /// Months for `.warranty`, days for `.returnWindow`.
    var duration: Int
    var isInferred: Bool
}

// MARK: - Bridge from cloud + rules output

extension ReceiptExtraction {
    /// Confidence assigned to fields the wire doesn't score directly.
    /// Printed/explicit values sit well above the LOW threshold; inferred
    /// or fallback values sit just below it so the amber marker appears.
    private enum Derived {
        static let printed: Double = 0.95
        static let inferred: Double = 0.6
    }

    static func from(
        receipt: ExtractedReceipt,
        confidences: FieldConfidences? = nil,
        lineItems: [ReceiptLineItem] = []
    ) -> ReceiptExtraction {
        let merchant = Self.trimmed(receipt.merchant)
        let itemName = Self.trimmed(receipt.itemName)
        let currency = Self.trimmed(receipt.currency)?.uppercased()
        let purchaseDate = Self.parseISODate(receipt.purchaseDate)

        var extraction = ReceiptExtraction(
            itemName: Field(
                value: itemName,
                confidence: itemName.map { _ in Derived.printed }
            ),
            merchant: Field(
                value: merchant,
                confidence: merchant.map { _ in confidences?.merchant ?? Derived.printed }
            ),
            total: Field(
                value: receipt.price > 0 ? Decimal(receipt.price) : nil,
                confidence: receipt.price > 0 ? confidences?.total : nil
            ),
            currency: Field(
                value: currency,
                confidence: currency.map { _ in Derived.printed }
            ),
            purchaseDate: Field(
                value: purchaseDate,
                confidence: purchaseDate.map { _ in confidences?.purchaseDate ?? Derived.printed }
            ),
            coverage: Self.coverageField(from: receipt)
        )
        extraction.category = receipt.category.trimmingCharacters(in: .whitespacesAndNewlines)
        extraction.lineItems = lineItems
        return extraction
    }

    /// Warranty wins over return window when both present — the confirm
    /// screen carries a single coverage term.
    private static func coverageField(from receipt: ExtractedReceipt) -> Field<CoverageEstimate> {
        if receipt.warrantyDurationMonths > 0 {
            return Field(
                value: CoverageEstimate(
                    kind: .warranty,
                    duration: receipt.warrantyDurationMonths,
                    isInferred: receipt.warrantyIsInferred
                ),
                confidence: receipt.warrantyIsInferred ? Derived.inferred : Derived.printed
            )
        }
        if receipt.returnWindowDays > 0 {
            return Field(
                value: CoverageEstimate(
                    kind: .returnWindow,
                    duration: receipt.returnWindowDays,
                    isInferred: receipt.returnWindowIsInferred
                ),
                confidence: receipt.returnWindowIsInferred ? Derived.inferred : Derived.printed
            )
        }
        return Field()
    }

    private static func trimmed(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private static func parseISODate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: string) { return date }
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd"
        fallback.locale = Locale(identifier: "en_US_POSIX")
        return fallback.date(from: string)
    }
}

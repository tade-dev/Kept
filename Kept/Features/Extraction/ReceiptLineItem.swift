import Foundation

/// A single purchased line on a receipt (name + price).
struct ReceiptLineItem: Codable, Equatable, Sendable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var price: Double

    init(id: UUID = UUID(), name: String, price: Double) {
        self.id = id
        self.name = name
        self.price = price
    }

    enum CodingKeys: String, CodingKey {
        case name, price
        // id is local-only for SwiftUI; regenerate on decode.
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        name = try container.decode(String.self, forKey: .name)
        price = try container.decode(Double.self, forKey: .price)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(price, forKey: .price)
    }

    static func encodeList(_ items: [ReceiptLineItem]) -> Data? {
        guard !items.isEmpty else { return nil }
        return try? JSONEncoder().encode(items)
    }

    static func decodeList(_ data: Data?) -> [ReceiptLineItem] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([ReceiptLineItem].self, from: data)) ?? []
    }
}

/// Cloud extract payload: structured receipt fields plus optional line items.
struct CloudExtractionPayload: Sendable, Equatable {
    var receipt: ExtractedReceipt
    var lineItems: [ReceiptLineItem]
    /// Per-field confidence from the wire response. Nil when the payload
    /// came from the rules floor alone (no cloud signal).
    var fieldConfidences: FieldConfidences?

    init(
        receipt: ExtractedReceipt,
        lineItems: [ReceiptLineItem],
        fieldConfidences: FieldConfidences? = nil
    ) {
        self.receipt = receipt
        self.lineItems = lineItems
        self.fieldConfidences = fieldConfidences
    }
}

/// Wire-level per-field confidences. Only the fields the gateway reports
/// live here — derived confidences (itemName, currency, coverage) come from
/// the extraction bridge, not from the wire.
struct FieldConfidences: Sendable, Equatable {
    var merchant: Double?
    var total: Double?
    var purchaseDate: Double?
}

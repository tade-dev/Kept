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
    /// Server-side document classification. See DocumentType.
    var documentType: DocumentType

    init(
        receipt: ExtractedReceipt,
        lineItems: [ReceiptLineItem],
        fieldConfidences: FieldConfidences? = nil,
        documentType: DocumentType = .receipt
    ) {
        self.receipt = receipt
        self.lineItems = lineItems
        self.fieldConfidences = fieldConfidences
        self.documentType = documentType
    }
}

/// What kind of document the cloud classifier decided this is. Only `.receipt`
/// proceeds to the review screen; everything else routes to the rejection sheet.
enum DocumentType: String, Sendable, Equatable, Identifiable {
    var id: String { rawValue }

    case receipt          // includes invoices, bills, sales slips
    case passport
    case idCard           // driver's license, national ID, membership card
    case businessCard
    case handwrittenNote
    case menu
    case letter
    case other

    /// Maps the raw string the LLM returned (any case, snake or camel) to a
    /// case. Unknown strings become `.other`. Nil or empty become `.receipt`
    /// (fail-open — pre-classification workers didn't send the field).
    static func from(_ raw: String?) -> DocumentType {
        guard let raw, !raw.isEmpty else { return .receipt }
        switch raw.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "receipt", "invoice", "bill":       return .receipt
        case "passport":                         return .passport
        case "id_card", "idcard", "id":          return .idCard
        case "business_card", "businesscard":    return .businessCard
        case "handwritten_note", "handwrittennote", "handwritten", "note":
                                                 return .handwrittenNote
        case "menu":                             return .menu
        case "letter":                           return .letter
        default:                                 return .other
        }
    }

    var isReceipt: Bool { self == .receipt }

    /// Display name for the rubber-stamp reveal ("PASSPORT", "MENU", etc.)
    var stampLabel: String {
        switch self {
        case .receipt:         "RECEIPT"
        case .passport:        "PASSPORT"
        case .idCard:          "ID CARD"
        case .businessCard:    "BUSINESS CARD"
        case .handwrittenNote: "HANDWRITTEN"
        case .menu:            "MENU"
        case .letter:          "LETTER"
        case .other:           "UNKNOWN"
        }
    }

    /// Warm one-liner shown below the stamp.
    var friendlyExplanation: String {
        switch self {
        case .receipt:         "This is a receipt."
        case .passport:        "Kept tracks receipts, not passports."
        case .idCard:          "Kept tracks receipts, not ID cards."
        case .businessCard:    "That looks like a business card."
        case .handwrittenNote: "Kept works best with printed receipts."
        case .menu:            "That's a menu — no total to track yet."
        case .letter:          "That looks like a letter, not a receipt."
        case .other:           "Doesn't look like a receipt."
        }
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

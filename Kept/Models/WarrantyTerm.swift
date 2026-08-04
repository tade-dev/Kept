import Foundation
import SwiftData

enum WarrantySource: String, Codable {
    case inferred
    case userSet
}

@Model
final class WarrantyTerm {
    var durationMonths: Int
    var expiryDate: Date
    var sourceRaw: String
    var confidence: Double
    var purchase: Purchase?

    var source: WarrantySource {
        get { WarrantySource(rawValue: sourceRaw) ?? .inferred }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        durationMonths: Int,
        expiryDate: Date,
        source: WarrantySource,
        confidence: Double
    ) {
        self.durationMonths = durationMonths
        self.expiryDate = expiryDate
        self.sourceRaw = source.rawValue
        self.confidence = confidence
    }
}

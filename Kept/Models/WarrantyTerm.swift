import Foundation
import SwiftData

enum WarrantySource: String, Sendable {
    case inferred
    case userProvided

    /// Accepts legacy `userSet` raw values written before the rename.
    init(stored: String) {
        switch stored {
        case Self.userProvided.rawValue, "userSet":
            self = .userProvided
        default:
            self = .inferred
        }
    }
}

@Model
final class WarrantyTerm {
    var durationMonths: Int = 0
    var expiryDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    var sourceRaw: String = "inferred"
    var confidence: Double = 0
    var purchase: Purchase?

    var source: WarrantySource {
        get { WarrantySource(stored: sourceRaw) }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        durationMonths: Int = 0,
        expiryDate: Date = .now,
        source: WarrantySource = .inferred,
        confidence: Double = 0
    ) {
        self.durationMonths = durationMonths
        self.expiryDate = expiryDate
        self.sourceRaw = source.rawValue
        self.confidence = confidence
    }
}

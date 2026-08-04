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

enum CoverageKind: String, Sendable {
    case warranty
    case returnWindow

    init(stored: String) {
        self = CoverageKind(rawValue: stored) ?? .warranty
    }
}

@Model
final class WarrantyTerm {
    var durationMonths: Int = 0
    /// Used when `kind` is `.returnWindow` (returns are day-based).
    var durationDays: Int = 0
    var expiryDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    var sourceRaw: String = "inferred"
    var kindRaw: String = "warranty"
    var confidence: Double = 0
    var purchase: Purchase?

    var source: WarrantySource {
        get { WarrantySource(stored: sourceRaw) }
        set { sourceRaw = newValue.rawValue }
    }

    var kind: CoverageKind {
        get { CoverageKind(stored: kindRaw) }
        set { kindRaw = newValue.rawValue }
    }

    init(
        durationMonths: Int = 0,
        durationDays: Int = 0,
        expiryDate: Date = .now,
        source: WarrantySource = .inferred,
        kind: CoverageKind = .warranty,
        confidence: Double = 0
    ) {
        self.durationMonths = durationMonths
        self.durationDays = durationDays
        self.expiryDate = expiryDate
        self.sourceRaw = source.rawValue
        self.kindRaw = kind.rawValue
        self.confidence = confidence
    }
}

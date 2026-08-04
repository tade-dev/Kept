import Foundation
import SwiftData

/// Local record of a Wallet pass tied to a purchase. Signing happens off-device.
@Model
final class PassRecord {
    var serialNumber: String = ""
    var addedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    var purchase: Purchase?

    init(serialNumber: String = "", addedAt: Date = .now) {
        self.serialNumber = serialNumber
        self.addedAt = addedAt
    }
}

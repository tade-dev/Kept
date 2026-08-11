import Foundation

/// Raw-String so new kinds can land without a CloudKit migration.
enum DocumentKind: String, Sendable, CaseIterable {
    case receipt

    init(stored: String) {
        self = DocumentKind(rawValue: stored) ?? .receipt
    }
}

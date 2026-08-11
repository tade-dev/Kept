import Foundation

/// Per-field visual state on the extraction confirm screen.
/// Missing beats Low — no value means no confidence.
enum ConfidenceState: Equatable {
    case high
    case low
    case missing

    /// Threshold below which a present value is flagged as "Check this".
    static let floor: Double = 0.8

    static func evaluate<T>(_ value: T?, confidence: Double?) -> ConfidenceState {
        guard value != nil else { return .missing }
        guard let confidence, confidence >= floor else { return .low }
        return .high
    }

    /// String overload — empty / whitespace counts as missing.
    static func evaluate(string value: String?, confidence: Double?) -> ConfidenceState {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return .missing }
        guard let confidence, confidence >= floor else { return .low }
        return .high
    }

    var needsAttention: Bool { self != .high }
}

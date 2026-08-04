import Foundation

protocol ExtractionService: Sendable {
    func extract(from lines: [RecognizedLine]) async throws -> ExtractedReceipt
}

enum ExtractionError: Error, LocalizedError {
    case modelUnavailable(reason: String)
    case emptyInput
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            "The on-device model isn't available: \(reason)."
        case .emptyInput:
            "No text was recognized on the receipt."
        case .underlying(let error):
            error.localizedDescription
        }
    }
}

/// Rules always run. Foundation Models enrich when available; failures fall back to rules.
struct DefaultExtractionService: ExtractionService {
    var rules: RulesExtractor = RulesExtractor()
    var model: ModelExtractor = ModelExtractor()

    func extract(from lines: [RecognizedLine]) async throws -> ExtractedReceipt {
        guard !lines.isEmpty else { throw ExtractionError.emptyInput }

        let floor = rules.extract(from: lines)
        guard model.isAvailable else { return floor }

        do {
            return try await model.enrich(lines: lines, using: floor)
        } catch {
            return floor
        }
    }
}

/// Back-compat aliases.
typealias ReceiptExtracting = ExtractionService
typealias ReceiptExtractionError = ExtractionError
typealias FoundationReceiptExtractor = DefaultExtractionService

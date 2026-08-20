import Foundation

/// Where the content being extracted came from. The worker prompt is
/// expected to branch on this — receipts have spatial layout and clear
/// TOTAL lines; emails are prose with the merchant in the sender, the
/// total scattered across a table, and multiple candidate dates.
///
/// Defaulted to `.receipt` on every entry point so existing call sites
/// (camera capture, re-extract) keep behaving exactly as they did.
enum ExtractionSource: String, Sendable {
    case receipt
    case email
}

protocol ExtractionService: Sendable {
    func extract(from lines: [RecognizedLine], source: ExtractionSource) async throws -> ExtractedReceipt
}

extension ExtractionService {
    /// Convenience overload for the common receipt-scan path.
    func extract(from lines: [RecognizedLine]) async throws -> ExtractedReceipt {
        try await extract(from: lines, source: .receipt)
    }
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

/// Rules always run. Cloud enriches when configured; offline / failures soft-fail back to rules.
/// Foundation Models remain as a secondary enricher when cloud isn't configured.
struct DefaultExtractionService: ExtractionService {
    var rules: RulesExtractor = RulesExtractor()
    var cloud: CloudExtractor? = CloudExtractor.makeDefault()
    var model: ModelExtractor = ModelExtractor()

    func extract(from lines: [RecognizedLine], source: ExtractionSource) async throws -> ExtractedReceipt {
        guard !lines.isEmpty else { throw ExtractionError.emptyInput }

        let floor = rules.extract(from: lines)

        if let cloud {
            do {
                let remote = try await cloud.extract(from: lines, source: source)
                return CloudExtractor.merge(rules: floor, cloud: remote)
            } catch {
                // Soft-fail: never block capture. Caller should persist OCR for re-extract.
                return floor
            }
        }

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

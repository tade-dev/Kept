import Foundation

/// Rules-only extractor. Always available — the product floor and harness baseline.
struct RulesExtractionService: ExtractionService {
    var rules: RulesExtractor = RulesExtractor()

    func extract(from lines: [RecognizedLine]) async throws -> ExtractedReceipt {
        guard !lines.isEmpty else { throw ExtractionError.emptyInput }
        return rules.extract(from: lines)
    }
}

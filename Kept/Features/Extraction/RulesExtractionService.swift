import Foundation

/// Rules-only extractor. Always available — the product floor and harness baseline.
struct RulesExtractionService: ExtractionService {
    var rules: RulesExtractor = RulesExtractor()

    func extract(from lines: [RecognizedLine], source: ExtractionSource) async throws -> ExtractedReceipt {
        guard !lines.isEmpty else { throw ExtractionError.emptyInput }
        // Rules extractor doesn't branch on source — its heuristics are
        // purely positional/textual. The source flag matters only for
        // the cloud path.
        return rules.extract(from: lines)
    }
}

import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class ExtractionConfirmModel {
    enum FieldID: CaseIterable {
        case itemName, merchant, total, purchaseDate, coverage
    }

    // Editable state — bound directly to the form.
    var itemName: String
    var merchant: String
    var totalText: String
    var currency: String
    var purchaseDate: Date
    var coverageKind: CoverageKind
    var coverageDurationText: String

    // A touched field is a confirmed field.
    private(set) var touched: Set<FieldID> = []

    // Capture context, immutable — carried through save so re-extraction is possible.
    let receiptImage: UIImage?
    let ocrLines: [RecognizedLine]
    private let extraction: ReceiptExtraction

    init(image: UIImage?, ocrLines: [RecognizedLine], extraction: ReceiptExtraction) {
        self.receiptImage = image
        self.ocrLines = ocrLines
        self.extraction = extraction

        self.itemName = extraction.itemName.value ?? ""
        self.merchant = extraction.merchant.value ?? ""
        self.totalText = extraction.total.value.map(Self.formatDecimal) ?? ""
        self.currency = extraction.currency.value
            ?? Locale.current.currency?.identifier ?? "USD"
        // Missing date defaults to today — spec.
        self.purchaseDate = extraction.purchaseDate.value ?? .now
        self.coverageKind = extraction.coverage.value?.kind ?? .warranty
        self.coverageDurationText = extraction.coverage.value
            .map { String($0.duration) } ?? ""
    }

    // MARK: - Per-field state

    func state(for field: FieldID) -> ConfidenceState {
        if touched.contains(field) { return .high }
        switch field {
        case .itemName:
            return .evaluate(string: itemName, confidence: extraction.itemName.confidence)
        case .merchant:
            return .evaluate(string: merchant, confidence: extraction.merchant.confidence)
        case .total:
            return .evaluate(parsedTotal, confidence: extraction.total.confidence)
        case .purchaseDate:
            // Date always has a value (defaulted to today), so a nil source
            // means the extractor gave nothing — flag as missing regardless.
            return extraction.purchaseDate.value == nil
                ? .missing
                : .evaluate(purchaseDate, confidence: extraction.purchaseDate.confidence)
        case .coverage:
            let duration = Int(coverageDurationText) ?? 0
            return duration > 0
                ? .evaluate(duration, confidence: extraction.coverage.confidence)
                : .missing
        }
    }

    /// Inferred coverage stays captioned "Estimated" until touched, regardless
    /// of confidence — the duration was a guess even when a confident one.
    var coverageIsEstimated: Bool {
        !touched.contains(.coverage) && (extraction.coverage.value?.isInferred == true)
    }

    var anyFieldNeedsAttention: Bool {
        FieldID.allCases.contains { state(for: $0).needsAttention }
    }

    // MARK: - Editing

    func markTouched(_ field: FieldID) { touched.insert(field) }

    // MARK: - Save

    /// Writes the Purchase into the context and returns it. Never blocks on
    /// low confidence. Caller triggers pass generation from the returned
    /// Purchase — failure there must not undo the save.
    @discardableResult
    func save(into context: ModelContext) -> Purchase {
        let purchase = Purchase(
            merchant: merchant.trimmingCharacters(in: .whitespaces),
            itemName: itemName.trimmingCharacters(in: .whitespaces),
            price: parsedTotal ?? 0,
            currency: currency.uppercased(),
            purchaseDate: purchaseDate,
            receiptImage: receiptImage?.jpegData(compressionQuality: 0.85),
            ocrLinesData: OCRLinePayload.encode(ocrLines)
        )
        purchase.documentKind = .receipt

        let duration = Int(coverageDurationText) ?? 0
        if duration > 0 {
            let byUser = touched.contains(.coverage)
            switch coverageKind {
            case .warranty:
                _ = purchase.setDuration(months: duration, byUser: byUser)
            case .returnWindow:
                _ = purchase.setReturnWindow(days: duration, byUser: byUser)
            }
        }

        context.insert(purchase)
        return purchase
    }

    // MARK: - Parsing helpers

    private var parsedTotal: Decimal? {
        let normalised = totalText.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalised), value > 0 else { return nil }
        return value
    }

    private static func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }
}

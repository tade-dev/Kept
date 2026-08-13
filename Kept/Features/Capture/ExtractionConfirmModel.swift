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
    /// Sticky flag: user explicitly chose Custom. Keeps the custom editor
    /// visible even when values happen to match a preset (e.g. 12 months warranty).
    var coverageCustomActive: Bool = false
    var lineItems: [ReceiptLineItem]

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
        self.lineItems = extraction.lineItems
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

    // MARK: - Coverage presets

    enum CoveragePreset: Hashable, CaseIterable {
        case none, return14, return30, warranty1yr, warranty2yr, custom

        var label: String {
            switch self {
            case .none: "None"
            case .return14: "14-day return"
            case .return30: "30-day return"
            case .warranty1yr: "1yr warranty"
            case .warranty2yr: "2yr warranty"
            case .custom: "Custom…"
            }
        }

        var kind: CoverageKind? {
            switch self {
            case .none, .custom: nil
            case .return14, .return30: .returnWindow
            case .warranty1yr, .warranty2yr: .warranty
            }
        }

        var duration: Int {
            switch self {
            case .none, .custom: 0
            case .return14: 14
            case .return30: 30
            case .warranty1yr: 12
            case .warranty2yr: 24
            }
        }
    }

    /// Which chip is currently selected. Custom is sticky once chosen; otherwise
    /// we match current values to a preset, falling back to Custom if none fits.
    var selectedCoveragePreset: CoveragePreset {
        if coverageCustomActive { return .custom }
        let duration = Int(coverageDurationText) ?? 0
        if duration <= 0 { return .none }
        for preset in CoveragePreset.allCases where preset != .custom && preset != .none {
            if preset.kind == coverageKind && preset.duration == duration {
                return preset
            }
        }
        return .custom
    }

    func applyCoveragePreset(_ preset: CoveragePreset) {
        markTouched(.coverage)
        switch preset {
        case .none:
            coverageCustomActive = false
            coverageDurationText = ""
        case .custom:
            coverageCustomActive = true
            // Seed only if we were coming from empty — otherwise keep whatever
            // the user (or the LLM) had so they can tweak.
            if (Int(coverageDurationText) ?? 0) == 0 {
                coverageKind = .warranty
                coverageDurationText = "12"
            }
        default:
            coverageCustomActive = false
            if let kind = preset.kind {
                coverageKind = kind
            }
            coverageDurationText = String(preset.duration)
        }
    }

    // MARK: - Line item edits

    func addLineItem() {
        lineItems.append(ReceiptLineItem(name: "", price: 0))
    }

    func removeLineItem(id: UUID) {
        lineItems.removeAll { $0.id == id }
    }

    /// Strips empty/zero rows so freshly-added blank items don't get persisted.
    private var cleanedLineItems: [ReceiptLineItem] {
        lineItems.compactMap { raw in
            let name = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, raw.price > 0 else { return nil }
            return ReceiptLineItem(id: raw.id, name: name, price: raw.price)
        }
    }

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
            ocrLinesData: OCRLinePayload.encode(ocrLines),
            lineItemsData: ReceiptLineItem.encodeList(cleanedLineItems)
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

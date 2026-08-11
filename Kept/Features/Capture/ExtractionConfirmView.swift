import SwiftUI
import SwiftData

/// Fields + save bar for the extraction confirm screen. Renders inline —
/// the receipt image is drawn by the parent (see `CaptureView`) so the
/// scanning → confirm morph animates through a single shared image.
struct ExtractionConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var model: ExtractionConfirmModel
    @State private var savedTick = 0

    /// Fires with the inserted Purchase. Save is already committed by then;
    /// parent decides what to close (nav pop vs sheet dismiss).
    var onSave: ((Purchase) -> Void)?

    init(
        image: UIImage?,
        ocrLines: [RecognizedLine],
        extraction: ReceiptExtraction,
        onSave: ((Purchase) -> Void)? = nil
    ) {
        _model = State(
            initialValue: ExtractionConfirmModel(
                image: image,
                ocrLines: ocrLines,
                extraction: extraction
            )
        )
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                receiptImage
                fields
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { saveBar }
        .sensoryFeedback(.success, trigger: savedTick)
    }

    @ViewBuilder
    private var receiptImage: some View {
        if let image = model.receiptImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            row(.itemName, label: "Item") {
                TextField("Add", text: $model.itemName)
                    .textInputAutocapitalization(.words)
                    .onChange(of: model.itemName) { _, _ in model.markTouched(.itemName) }
            }

            row(.merchant, label: "Merchant") {
                TextField("Add", text: $model.merchant)
                    .textInputAutocapitalization(.words)
                    .onChange(of: model.merchant) { _, _ in model.markTouched(.merchant) }
            }

            row(.total, label: "Total") {
                HStack(spacing: Spacing.sm) {
                    TextField("Add", text: $model.totalText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .onChange(of: model.totalText) { _, _ in model.markTouched(.total) }
                    TextField("CUR", text: $model.currency)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                }
            }

            row(.purchaseDate, label: "Purchased") {
                DatePicker(
                    "",
                    selection: $model.purchaseDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .onChange(of: model.purchaseDate) { _, _ in model.markTouched(.purchaseDate) }
            }

            coverageRow
        }
    }

    private var coverageRow: some View {
        row(.coverage, label: "Cover", extraCaption: model.coverageIsEstimated ? "Estimated" : nil) {
            HStack(spacing: Spacing.sm) {
                TextField("Add", text: $model.coverageDurationText)
                    .keyboardType(.numberPad)
                    .monospacedDigit()
                    .frame(maxWidth: 96)
                    .onChange(of: model.coverageDurationText) { _, _ in model.markTouched(.coverage) }
                Picker("", selection: $model.coverageKind) {
                    Text("months warranty").tag(CoverageKind.warranty)
                    Text("days to return").tag(CoverageKind.returnWindow)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: model.coverageKind) { _, _ in model.markTouched(.coverage) }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Row builder

    @ViewBuilder
    private func row<Content: View>(
        _ field: ExtractionConfirmModel.FieldID,
        label: String,
        extraCaption: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let state = model.state(for: field)
        let caption: String? = {
            if let extraCaption { return extraCaption }
            switch state {
            case .low: return "Check this"
            case .missing, .high: return nil
            }
        }()

        HStack(alignment: .top, spacing: Spacing.sm) {
            Rectangle()
                .fill(state.needsAttention ? KeptColor.endingSoon : .clear)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                content()
                    .font(.body)
                if let caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(KeptColor.endingSoon)
                        .accessibilityHint(caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: Spacing.sm) {
            if model.anyFieldNeedsAttention {
                Text("Check the highlighted fields.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: save) {
                Text("Save receipt")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(KeptColor.ink)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .background(.bar)
    }

    private func save() {
        let purchase = model.save(into: modelContext)
        savedTick &+= 1
        Task { await CoverageNotificationScheduler.reschedule(for: purchase) }
        // Parent decides how to close (pop nav vs. dismiss sheet) when a
        // callback is provided — otherwise fall back to environment dismiss.
        if let onSave {
            onSave(purchase)
        } else {
            dismiss()
        }
    }
}

// MARK: - Previews

#Preview("All high") {
    NavigationStack {
        ExtractionConfirmView(
            image: PreviewFixtures.image,
            ocrLines: [],
            extraction: PreviewFixtures.allHigh
        )
    }
    .modelContainer(for: [Purchase.self, WarrantyTerm.self, PassRecord.self], inMemory: true)
}

#Preview("Mixed") {
    NavigationStack {
        ExtractionConfirmView(
            image: PreviewFixtures.image,
            ocrLines: [],
            extraction: PreviewFixtures.mixed
        )
    }
    .modelContainer(for: [Purchase.self, WarrantyTerm.self, PassRecord.self], inMemory: true)
}

#Preview("All missing") {
    NavigationStack {
        ExtractionConfirmView(
            image: PreviewFixtures.image,
            ocrLines: [],
            extraction: .empty
        )
    }
    .modelContainer(for: [Purchase.self, WarrantyTerm.self, PassRecord.self], inMemory: true)
}

private enum PreviewFixtures {
    static let image: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200))
        return renderer.image { ctx in
            UIColor.systemGray5.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            UIColor.darkGray.setFill()
            UIBezierPath(roundedRect: CGRect(x: 30, y: 20, width: 240, height: 160), cornerRadius: 8).fill()
        }
    }()

    static let allHigh = ReceiptExtraction(
        itemName: .init(value: "MacBook Pro 14\"", confidence: 0.97),
        merchant: .init(value: "Apple Store", confidence: 0.99),
        total: .init(value: Decimal(1999), confidence: 0.98),
        currency: .init(value: "USD", confidence: 0.98),
        purchaseDate: .init(value: .now, confidence: 0.95),
        coverage: .init(value: CoverageEstimate(kind: .warranty, duration: 12, isInferred: false), confidence: 0.9)
    )

    static let mixed = ReceiptExtraction(
        itemName: .init(value: "Winter Jacket", confidence: 0.62),   // low
        merchant: .init(value: "Uniqlo", confidence: 0.9),            // high
        total: .init(value: Decimal(129.90), confidence: 0.55),      // low
        currency: .init(value: "GBP", confidence: 0.9),               // high
        purchaseDate: .init(),                                        // missing
        coverage: .init(value: CoverageEstimate(kind: .returnWindow, duration: 30, isInferred: true), confidence: 0.7)
    )
}

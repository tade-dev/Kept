import SwiftUI
import SwiftData

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var isScannerPresented: Bool
    @State private var capturedImage: UIImage?
    @State private var recognizedLines: [RecognizedLine] = []
    @State private var extraction: ExtractedReceipt?
    @State private var extractionErrorMessage: String?
    @State private var status: Status = .idle

    @State private var merchant: String = ""
    @State private var itemName: String = ""
    @State private var priceText: String = ""
    @State private var currencyText: String = Locale.current.currency?.identifier ?? "USD"
    @State private var purchaseDate: Date = .now
    @State private var warrantyMonthsText: String = ""
    @State private var warrantyInferred: Bool = false
    @State private var warrantyEditedByUser: Bool = false

    private let recognizer: any TextRecognizing
    private let extractor: any ReceiptExtracting
    private let preloadedImage: UIImage?

    init(
        image: UIImage? = nil,
        recognizer: any TextRecognizing = VisionTextRecognizer(),
        extractor: any ReceiptExtracting = FoundationReceiptExtractor()
    ) {
        self.recognizer = recognizer
        self.extractor = extractor
        self.preloadedImage = image
        self._isScannerPresented = State(initialValue: image == nil)
        self._capturedImage = State(initialValue: image)
    }

    enum Status: Equatable {
        case idle
        case scanning
        case recognizing
        case extracting
        case review
        case failed
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if status == .review {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Save", action: save)
                                .disabled(!canSave)
                        }
                    }
                }
                .sheet(isPresented: $isScannerPresented) {
                    DocumentScanner { result in
                        isScannerPresented = false
                        handleScan(result)
                    }
                    .ignoresSafeArea()
                }
                .task {
                    if let preloadedImage, status == .idle {
                        await runPipeline(on: preloadedImage)
                    }
                }
        }
    }

    private var navigationTitle: String {
        switch status {
        case .review: "Review receipt"
        default: "Scan receipt"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .idle, .scanning:
            emptyScannerState
        case .recognizing:
            progress("Reading receipt…")
        case .extracting:
            progress("Understanding warranty…")
        case .review:
            reviewForm
        case .failed:
            failureState
        }
    }

    private var emptyScannerState: some View {
        ContentUnavailableView(
            "Point at a receipt",
            systemImage: "doc.viewfinder",
            description: Text("Kept will crop, straighten, and read it on-device.")
        )
    }

    private func progress(_ label: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failureState: some View {
        ContentUnavailableView(
            "Couldn't read that",
            systemImage: "exclamationmark.triangle",
            description: Text(extractionErrorMessage ?? "Try again with better light.")
        )
    }

    private var reviewForm: some View {
        Form {
            if let image = capturedImage {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(.init())
                }
            }

            Section("Purchase") {
                TextField("Merchant", text: $merchant)
                TextField("Item", text: $itemName)
                HStack {
                    TextField("Price", text: $priceText)
                        .keyboardType(.decimalPad)
                    TextField("CUR", text: $currencyText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Purchased", selection: $purchaseDate, displayedComponents: .date)
            }

            Section {
                HStack {
                    TextField("Duration (months)", text: $warrantyMonthsText)
                        .keyboardType(.numberPad)
                        .onChange(of: warrantyMonthsText) { _, _ in warrantyEditedByUser = true }
                    if warrantyInferred && !warrantyEditedByUser {
                        Text("inferred")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                if let expiry = expiryDate {
                    LabeledContent("Expires") {
                        Text(expiry, format: .dateTime.day().month().year())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Warranty")
            } footer: {
                if warrantyInferred && !warrantyEditedByUser {
                    Text("Kept guessed this length from the merchant. Edit if you know better.")
                }
            }

            if let extractionErrorMessage {
                Section {
                    Label(extractionErrorMessage, systemImage: "sparkles")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
        }
    }

    private var expiryDate: Date? {
        guard let months = Int(warrantyMonthsText), months > 0 else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: purchaseDate)
    }

    private var canSave: Bool {
        !merchant.trimmingCharacters(in: .whitespaces).isEmpty
            && !itemName.trimmingCharacters(in: .whitespaces).isEmpty
            && (Decimal(string: priceText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
    }

    private func handleScan(_ result: Result<[UIImage], DocumentScanner.ScanError>) {
        switch result {
        case .success(let images):
            guard let first = images.first else {
                dismiss()
                return
            }
            capturedImage = first
            Task { await runPipeline(on: first) }
        case .failure(.cancelled):
            dismiss()
        case .failure(let error):
            extractionErrorMessage = error.errorDescription
            status = .failed
        }
    }

    private func runPipeline(on image: UIImage) async {
        status = .recognizing
        let lines: [RecognizedLine]
        do {
            lines = try await recognizer.recognize(in: image)
        } catch {
            extractionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .failed
            return
        }
        recognizedLines = lines

        if lines.isEmpty {
            extractionErrorMessage = "No text was recognised on this receipt."
            enterManualReview()
            return
        }

        status = .extracting
        do {
            let result = try await extractor.extract(from: lines)
            extraction = result
            applyExtraction(result)
            status = .review
        } catch {
            extractionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            enterManualReview()
        }
    }

    private func enterManualReview() {
        // Fall back to a blank editable form so the user isn't blocked when
        // the on-device model is unavailable (e.g., pre-Apple-Intelligence devices).
        status = .review
    }

    private func applyExtraction(_ result: ExtractedReceipt) {
        merchant = result.merchant
        itemName = result.itemName
        priceText = formatted(result.price)
        currencyText = result.currency.uppercased()
        purchaseDate = parseISODate(result.purchaseDate) ?? .now
        warrantyMonthsText = result.warrantyDurationMonths > 0 ? String(result.warrantyDurationMonths) : ""
        warrantyInferred = result.warrantyIsInferred
        warrantyEditedByUser = false
    }

    private func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func parseISODate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: string) { return date }
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd"
        fallback.locale = Locale(identifier: "en_US_POSIX")
        return fallback.date(from: string)
    }

    private func save() {
        let normalisedPrice = priceText.replacingOccurrences(of: ",", with: ".")
        let price = Decimal(string: normalisedPrice) ?? 0
        let months = Int(warrantyMonthsText) ?? 0

        let purchase = Purchase(
            merchant: merchant.trimmingCharacters(in: .whitespaces),
            itemName: itemName.trimmingCharacters(in: .whitespaces),
            price: price,
            currency: currencyText.uppercased(),
            purchaseDate: purchaseDate,
            notes: "",
            receiptImage: capturedImage?.jpegData(compressionQuality: 0.85)
        )

        if months > 0 {
            let expiry = Calendar.current.date(byAdding: .month, value: months, to: purchaseDate) ?? purchaseDate
            let source: WarrantySource = warrantyEditedByUser ? .userSet
                : (extraction?.warrantyIsInferred == true ? .inferred : .userSet)
            let warranty = WarrantyTerm(
                durationMonths: months,
                expiryDate: expiry,
                source: source,
                confidence: extraction?.confidence ?? 1.0
            )
            purchase.warranty = warranty
        }

        modelContext.insert(purchase)
        dismiss()
    }
}

#Preview("Scanning empty state") {
    CaptureView(
        recognizer: PreviewRecognizer(),
        extractor: PreviewExtractor()
    )
    .modelContainer(for: [Purchase.self, WarrantyTerm.self], inMemory: true)
}

#Preview("Review with extracted data") {
    CaptureView(
        image: PreviewSampleImage.receipt,
        recognizer: PreviewRecognizer(),
        extractor: PreviewExtractor()
    )
    .modelContainer(for: [Purchase.self, WarrantyTerm.self], inMemory: true)
}

private struct PreviewRecognizer: TextRecognizing {
    func recognize(in image: UIImage) async throws -> [RecognizedLine] {
        [
            RecognizedLine(text: "APPLE STORE", confidence: 0.99, boundingBox: CGRect(x: 0, y: 0.9, width: 1, height: 0.05)),
            RecognizedLine(text: "MacBook Pro 14\"", confidence: 0.96, boundingBox: CGRect(x: 0, y: 0.7, width: 1, height: 0.05)),
            RecognizedLine(text: "$1,999.00", confidence: 0.98, boundingBox: CGRect(x: 0, y: 0.5, width: 1, height: 0.05))
        ]
    }
}

private struct PreviewExtractor: ReceiptExtracting {
    func extract(from lines: [RecognizedLine]) async throws -> ExtractedReceipt {
        try await Task.sleep(nanoseconds: 400_000_000)
        return ExtractedReceipt(
            merchant: "Apple Store",
            itemName: "MacBook Pro 14\"",
            price: 1999.00,
            currency: "USD",
            purchaseDate: "2026-08-01",
            warrantyDurationMonths: 12,
            warrantyIsInferred: true,
            confidence: 0.92
        )
    }
}

private enum PreviewSampleImage {
    static let receipt: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400))
        return renderer.image { ctx in
            UIColor.systemGray6.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
    }()
}

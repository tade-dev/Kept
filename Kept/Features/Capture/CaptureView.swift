import SwiftUI
import SwiftData

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var receiptNamespace

    /// Temporary flag while the confirm screen is being validated. Flip to
    /// false to fall back to the inline review Form.
    private let useConfirmScreen: Bool = true

    @State private var isScannerPresented: Bool
    @State private var capturedImage: UIImage?
    @State private var recognizedLines: [RecognizedLine] = []
    @State private var extraction: ExtractedReceipt?
    @State private var fieldConfidences: FieldConfidences?
    @State private var extractionErrorMessage: String?
    /// Cloud failed or offline — save still proceeds with rules floor + OCR for later.
    @State private var needsReextraction = false
    @State private var status: Status = .idle

    @State private var merchant: String = ""
    @State private var itemName: String = ""
    @State private var lineItems: [ReceiptLineItem] = []
    @State private var priceText: String = ""
    @State private var currencyText: String = Locale.current.currency?.identifier ?? "USD"
    @State private var purchaseDate: Date = .now
    @State private var warrantyMonthsText: String = ""
    @State private var warrantyInferred: Bool = false
    @State private var warrantyEditedByUser: Bool = false
    @State private var returnDaysText: String = ""
    @State private var returnInferred: Bool = false
    @State private var returnEditedByUser: Bool = false

    private let ocr: any OCRService
    private let rulesExtractor: RulesExtractor
    private let cloudExtractor: CloudExtractor?
    private let preloadedImage: UIImage?
    /// Fires with the freshly-inserted Purchase after Save. The sheet still
    /// dismisses itself; the parent uses this to highlight the new row.
    private let onSave: ((Purchase) -> Void)?

    init(
        image: UIImage? = nil,
        ocr: any OCRService = VisionOCRService(),
        rulesExtractor: RulesExtractor = RulesExtractor(),
        cloudExtractor: CloudExtractor? = CloudExtractor.makeDefault(),
        onSave: ((Purchase) -> Void)? = nil
    ) {
        self.ocr = ocr
        self.rulesExtractor = rulesExtractor
        self.cloudExtractor = cloudExtractor
        self.preloadedImage = image
        self.onSave = onSave
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

    private var isHoldingReceipt: Bool {
        capturedImage != nil && status != .idle && status != .scanning
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .toolbarTitleDisplayMode(.inline)
                .sensoryFeedback(.impact(weight: .light), trigger: status == .review)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if status == .review && !useConfirmScreen {
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
        case .recognizing, .extracting: "Reading receipt"
        default: "Scan receipt"
        }
    }

    @ViewBuilder
    private var content: some View {
        if isHoldingReceipt {
            heldReceiptFlow
        } else {
            switch status {
            case .failed:
                failureState
            default:
                emptyScannerState
            }
        }
    }

    // MARK: - Hold-the-receipt flow

    @ViewBuilder
    private var heldReceiptFlow: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if let image = capturedImage, status != .review {
                    heldReceiptImage(image)
                }

                if status == .review {
                    reviewContent
                        .transition(formTransition)
                } else {
                    Spacer(minLength: 0)
                }
            }

            if status != .review {
                processingChrome
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Loading-state image. In review, the confirm view owns the image so
    /// it scrolls with the fields like the detail view — no fixed header.
    private func heldReceiptImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 520)
            .processingShimmer(isActive: status == .recognizing || status == .extracting)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            .matchedGeometryEffect(id: "captureReceipt", in: receiptNamespace)
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .animation(statusAnimation, value: status)
    }

    private var processingChrome: some View {
        HStack(spacing: 12) {
            if status != .failed {
                ProgressView()
                    .controlSize(.regular)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(processingTitle)
                    .font(.subheadline.weight(.semibold))
                if let extractionErrorMessage, status == .failed {
                    Text(extractionErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(processingSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if status == .failed {
                Button("Edit anyway") {
                    transition(to: .review)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .animation(statusAnimation, value: status)
    }

    private var processingTitle: String {
        switch status {
        case .recognizing: "Reading receipt…"
        case .extracting: "Understanding warranty…"
        case .failed: "Couldn't finish reading"
        default: "Working…"
        }
    }

    private var processingSubtitle: String {
        switch status {
        case .recognizing: "On-device OCR"
        case .extracting: "Filling what we can"
        default: ""
        }
    }

    // MARK: - Review

    @ViewBuilder
    private var reviewContent: some View {
        if useConfirmScreen, let extraction {
            ExtractionConfirmView(
                image: capturedImage,
                ocrLines: recognizedLines,
                extraction: ReceiptExtraction.from(
                    receipt: extraction,
                    confidences: fieldConfidences,
                    lineItems: lineItems
                ),
                onSave: { purchase in
                    onSave?(purchase)
                    dismiss()
                }
            )
        } else {
            reviewForm
        }
    }

    private var reviewForm: some View {
        Form {
            Section("Purchase") {
                TextField("Merchant", text: $merchant)
                DatePicker("Purchased", selection: $purchaseDate, displayedComponents: .date)
                if lineItems.isEmpty {
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
                }
            }
            .transition(formTransition)

            if !lineItems.isEmpty {
                Section {
                    ForEach($lineItems) { $item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            TextField("Item", text: $item.name)
                            TextField(
                                "Price",
                                value: $item.price,
                                format: .number.precision(.fractionLength(0...2))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 72, maxWidth: 96)
                        }
                    }
                    .onDelete { lineItems.remove(atOffsets: $0) }

                    HStack {
                        Text("Total")
                            .fontWeight(.semibold)
                        Spacer()
                        TextField("Total", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 72, maxWidth: 96)
                        TextField("CUR", text: $currencyText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .frame(width: 52)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Items")
                } footer: {
                    Text("Tracked for warranty: \(itemName.isEmpty ? "—" : itemName)")
                }
                .transition(formTransition)
            }

            Section {
                HStack {
                    TextField("Days to return", text: $returnDaysText)
                        .keyboardType(.numberPad)
                        .onChange(of: returnDaysText) { _, _ in returnEditedByUser = true }
                    if returnInferred && !returnEditedByUser {
                        inferredChip
                    }
                }
                if let returnBy = returnExpiryDate {
                    LabeledContent("Return by") {
                        Text(returnBy, format: .dateTime.day().month().year())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Return window")
            } footer: {
                if returnInferred && !returnEditedByUser {
                    Text("Kept guessed the return window. Edit if the receipt says otherwise.")
                }
            }
            .transition(formTransition)

            Section {
                HStack {
                    TextField("Duration (months)", text: $warrantyMonthsText)
                        .keyboardType(.numberPad)
                        .onChange(of: warrantyMonthsText) { _, _ in warrantyEditedByUser = true }
                    if warrantyInferred && !warrantyEditedByUser {
                        inferredChip
                    }
                }
                if let expiry = warrantyExpiryDate {
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
                } else if (Int(warrantyMonthsText) ?? 0) == 0 {
                    Text("Leave blank for clothing and other purchases with no repair warranty.")
                }
            }
            .transition(formTransition)

            if let extractionErrorMessage {
                Section {
                    Label(extractionErrorMessage, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                .transition(formTransition)
            }

            #if DEBUG
            if needsReextraction {
                Section {
                    Label(
                        "Cloud extract failed — showing on-device rules parse. Check wrangler (0.0.0.0:8787) + Wi‑Fi.",
                        systemImage: "antenna.radiowaves.left.and.right.slash"
                    )
                    .foregroundStyle(.orange)
                    .font(.footnote)
                }
                .transition(formTransition)
            }
            #endif
        }
    }

    private var formTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            )
    }

    private var statusAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.32)
    }

    private func transition(to newStatus: Status) {
        if reduceMotion {
            status = newStatus
        } else {
            withAnimation(.snappy(duration: 0.32)) {
                status = newStatus
            }
        }
    }

    // MARK: - Empty / failure

    private var emptyScannerState: some View {
        ContentUnavailableView(
            "Point at a receipt",
            systemImage: "doc.viewfinder",
            description: Text("Kept will crop, straighten, and read it on-device.")
        )
    }

    private var failureState: some View {
        ContentUnavailableView(
            "Couldn't read that",
            systemImage: "exclamationmark.triangle",
            description: Text(extractionErrorMessage ?? "Try again with better light.")
        )
    }

    // MARK: - Logic

    private var inferredChip: some View {
        Text("inferred")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var warrantyExpiryDate: Date? {
        guard let months = Int(warrantyMonthsText), months > 0 else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: purchaseDate)
    }

    private var returnExpiryDate: Date? {
        guard let days = Int(returnDaysText), days > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: purchaseDate)
    }

    private var canSave: Bool {
        !merchant.trimmingCharacters(in: .whitespaces).isEmpty
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
            transition(to: .failed)
        }
    }

    private func runPipeline(on image: UIImage) async {
        transition(to: .recognizing)
        let lines: [RecognizedLine]
        do {
            lines = try await ocr.recognize(in: image)
        } catch {
            extractionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            transition(to: .failed)
            return
        }
        recognizedLines = lines

        if lines.isEmpty {
            extractionErrorMessage = "No text was recognised on this receipt."
            transition(to: .review)
            return
        }

        transition(to: .extracting)
        needsReextraction = false
        // Clear prior extract errors — cloud soft-fail must not surface mid-capture.
        extractionErrorMessage = nil

        let floor = rulesExtractor.extract(from: lines)
        if let cloudExtractor {
            do {
                let remote = try await cloudExtractor.extractDetailed(from: lines)
                let merged = CloudExtractor.merge(rules: floor, cloud: remote)
                extraction = merged.receipt
                fieldConfidences = merged.fieldConfidences
                applyExtraction(merged.receipt, lineItems: merged.lineItems)
            } catch {
                // Offline / 5xx / timeout: keep rules floor, mark for re-extract, no error UI.
                needsReextraction = true
                extraction = floor
                fieldConfidences = nil
                applyExtraction(floor, lineItems: [])
            }
        } else {
            extraction = floor
            fieldConfidences = nil
            applyExtraction(floor, lineItems: [])
        }
        transition(to: .review)
    }

    private func applyExtraction(_ result: ExtractedReceipt, lineItems items: [ReceiptLineItem]) {
        merchant = result.merchant
        itemName = result.itemName
        lineItems = items
        if itemName.isEmpty, let top = items.max(by: { $0.price < $1.price }) {
            itemName = top.name
        }
        priceText = result.price > 0 ? formatted(result.price) : ""
        currencyText = result.currency.uppercased()
        purchaseDate = parseISODate(result.purchaseDate) ?? .now
        warrantyMonthsText = result.warrantyDurationMonths > 0 ? String(result.warrantyDurationMonths) : ""
        warrantyInferred = result.warrantyIsInferred
        warrantyEditedByUser = false
        returnDaysText = result.returnWindowDays > 0 ? String(result.returnWindowDays) : ""
        returnInferred = result.returnWindowIsInferred
        returnEditedByUser = false
    }

    private func formatted(_ value: Double) -> String {
        // POSIX, no grouping — "2,849" would round-trip as 2.849 via comma→dot replace.
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
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
        let returnDays = Int(returnDaysText) ?? 0

        let cleanedItems = lineItems
            .map {
                ReceiptLineItem(
                    id: $0.id,
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    price: $0.price
                )
            }
            .filter { !$0.name.isEmpty && $0.price > 0 }

        var primaryName = itemName.trimmingCharacters(in: .whitespaces)
        if primaryName.isEmpty, let top = cleanedItems.max(by: { $0.price < $1.price }) {
            primaryName = top.name
        }

        let purchase = Purchase(
            merchant: merchant.trimmingCharacters(in: .whitespaces),
            itemName: primaryName,
            price: price,
            currency: currencyText.uppercased(),
            purchaseDate: purchaseDate,
            notes: "",
            receiptImage: capturedImage?.jpegData(compressionQuality: 0.85),
            ocrLinesData: OCRLinePayload.encode(recognizedLines),
            lineItemsData: ReceiptLineItem.encodeList(cleanedItems),
            needsReextraction: needsReextraction
        )

        if returnDays > 0 {
            let byUser = returnEditedByUser || extraction?.returnWindowIsInferred != true
            _ = purchase.setReturnWindow(days: returnDays, byUser: byUser)
            if !byUser, let term = purchase.returnWindow {
                term.source = .inferred
                term.confidence = extraction?.confidence ?? 0.7
            }
        }

        if months > 0 {
            let byUser = warrantyEditedByUser || extraction?.warrantyIsInferred != true
            _ = purchase.setDuration(months: months, byUser: byUser)
            if !byUser, let term = purchase.primaryWarranty {
                term.source = .inferred
                term.confidence = extraction?.confidence ?? 0.7
            }
        }

        modelContext.insert(purchase)
        Task {
            await CoverageNotificationScheduler.reschedule(for: purchase)
        }
        dismiss()
    }
}

#Preview("Scanning empty state") {
    CaptureView(
        ocr: PreviewOCR(),
        cloudExtractor: nil
    )
    .modelContainer(for: [Purchase.self, WarrantyTerm.self, PassRecord.self], inMemory: true)
}

#Preview("Review with extracted data") {
    CaptureView(
        image: PreviewSampleImage.receipt,
        ocr: PreviewOCR(delayNanoseconds: 800_000_000),
        cloudExtractor: nil
    )
    .modelContainer(for: [Purchase.self, WarrantyTerm.self, PassRecord.self], inMemory: true)
}

private struct PreviewOCR: OCRService {
    var delayNanoseconds: UInt64 = 0

    func recognize(in image: UIImage) async throws -> [RecognizedLine] {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return [
            RecognizedLine(text: "APPLE STORE", confidence: 0.99, boundingBox: CGRect(x: 0, y: 0.9, width: 1, height: 0.05)),
            RecognizedLine(text: "MacBook Pro 14\"", confidence: 0.96, boundingBox: CGRect(x: 0, y: 0.7, width: 1, height: 0.05)),
            RecognizedLine(text: "TOTAL $1,999.00", confidence: 0.98, boundingBox: CGRect(x: 0, y: 0.2, width: 1, height: 0.05)),
        ]
    }
}

private enum PreviewSampleImage {
    static let receipt: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400))
        return renderer.image { ctx in
            UIColor.systemGray6.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
            UIColor.darkGray.setFill()
            UIBezierPath(roundedRect: CGRect(x: 40, y: 40, width: 220, height: 320), cornerRadius: 8).fill()
        }
    }()
}

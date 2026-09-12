import SwiftUI
import SwiftData

struct PurchaseDetailView: View {
    @Bindable var purchase: Purchase
    @Environment(SubscriptionAccess.self) private var subscription

    @State private var warrantyMonthsText: String = ""
    @State private var returnDaysText: String = ""
    @State private var priceText: String = ""
    @State private var isShowingFullImage = false
    @State private var isReExtracting = false
    @State private var showReExtractPill = false
    @State private var reExtractTick = 0

    /// Heuristic: the original extraction produced too little to be useful.
    /// Doesn't consider warranty/return-window presence — many receipts
    /// (clothing, groceries) genuinely have no coverage, and re-extraction
    /// won't invent one. Focus on the printed fields that should be there
    /// when the image is legible: merchant, item, price.
    private var extractionLooksWeak: Bool {
        let merchant = purchase.merchant.trimmingCharacters(in: .whitespaces)
        let item = purchase.itemName.trimmingCharacters(in: .whitespaces)
        if purchase.needsReextraction { return true }
        return merchant.isEmpty || item.isEmpty || purchase.price <= 0
    }

    /// Re-extract needs *some* source of truth — either persisted OCR lines
    /// from capture, or the receipt image to re-OCR. Without both, the
    /// pill would be a broken promise.
    private var canReExtract: Bool {
        purchase.ocrLinesData != nil || purchase.receiptImage != nil
    }

    var body: some View {
        Form {
            if let data = purchase.receiptImage, let image = UIImage(data: data) {
                Section {
                    Button {
                        isShowingFullImage = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            Section("Purchase") {
                TextField("Merchant", text: $purchase.merchant)
                DatePicker(
                    "Purchased",
                    selection: $purchase.purchaseDate,
                    displayedComponents: .date
                )
                .onChange(of: purchase.purchaseDate) { _, _ in
                    recomputeExpiry()
                    Task { await CoverageNotificationScheduler.reschedule(for: purchase) }
                }
                if purchase.lineItems.isEmpty {
                    TextField("Item", text: $purchase.itemName)
                    HStack {
                        TextField("Price", text: $priceText)
                            .keyboardType(.decimalPad)
                            .onChange(of: priceText) { _, newValue in
                                let normalised = newValue.replacingOccurrences(of: ",", with: ".")
                                purchase.price = Decimal(string: normalised) ?? 0
                            }
                        TextField("CUR", text: $purchase.currency)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                TextField("Serial number", text: $purchase.serialNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
            }

            if !purchase.lineItems.isEmpty {
                Section {
                    ForEach(purchase.lineItems) { item in
                        LabeledContent {
                            Text(item.price, format: .number.precision(.fractionLength(0...2)))
                                .monospacedDigit()
                        } label: {
                            Text(item.name)
                        }
                    }
                    LabeledContent {
                        HStack(spacing: 8) {
                            TextField("Total", text: $priceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: priceText) { _, newValue in
                                    let normalised = newValue.replacingOccurrences(of: ",", with: ".")
                                    purchase.price = Decimal(string: normalised) ?? 0
                                }
                            Text(purchase.currency)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text("Total")
                            .fontWeight(.semibold)
                    }
                } header: {
                    Text("Items")
                } footer: {
                    Text("Tracked for warranty: \(purchase.displaySubtitle)")
                }
            }

            Section {
                HStack {
                    TextField("Days to return", text: $returnDaysText)
                        .keyboardType(.numberPad)
                        .onChange(of: returnDaysText) { _, newValue in
                            _ = purchase.setReturnWindow(days: Int(newValue) ?? 0, byUser: true)
                            Task { await CoverageNotificationScheduler.reschedule(for: purchase) }
                        }
                    if purchase.returnWindow?.source == .inferred {
                        inferredChip
                    }
                }
                if let term = purchase.returnWindow {
                    LabeledContent("Return by") {
                        Text(term.expiryDate, format: .dateTime.day().month().year())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Return window")
            } footer: {
                if purchase.returnWindow == nil {
                    Text("Optional. Clothing and many retailers allow returns for a short window.")
                } else if purchase.returnWindow?.source == .inferred {
                    Text("Kept guessed this return window. Edit it to override.")
                }
            }

            Section {
                HStack {
                    TextField("Duration (months)", text: $warrantyMonthsText)
                        .keyboardType(.numberPad)
                        .onChange(of: warrantyMonthsText) { _, newValue in
                            _ = purchase.setDuration(months: Int(newValue) ?? 0, byUser: true)
                            Task { await CoverageNotificationScheduler.reschedule(for: purchase) }
                        }
                    if purchase.primaryWarranty?.source == .inferred {
                        inferredChip
                    }
                }
                if let warranty = purchase.primaryWarranty {
                    LabeledContent("Expires") {
                        Text(warranty.expiryDate, format: .dateTime.day().month().year())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Warranty")
            } footer: {
                if purchase.primaryWarranty == nil {
                    Text("No repair warranty tracked. Leave blank for fashion and consumables.")
                } else if purchase.primaryWarranty?.source == .inferred {
                    Text("Kept guessed this length. Edit it to override.")
                }
            }

            Section("Notes") {
                TextField("Add a note", text: $purchase.notes, axis: .vertical)
                    .lineLimit(2...6)
            }

            if purchase.coverageEndsAt != nil || purchase.nextDeadline != nil {
                Section {
                    AddToWalletButton(purchase: purchase)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } footer: {
                    Text(
                        (purchase.passRecords ?? []).isEmpty
                            ? "Adds a countdown pass for this purchase to Apple Wallet."
                            : "Already in Wallet. You can add it again if you removed the pass."
                    )
                }
            }

            if purchase.documentKind == .receipt {
                Section {
                    ClaimPackButton(purchase: purchase)
                } header: {
                    Text("Claim pack")
                } footer: {
                    Text("A one-page PDF summary with receipt attached, send it to the seller when you need to claim.")
                }
            }
        }
        .font(.keptBody)  // cascades Bricolage to all Text descendants in the Form
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if showReExtractPill && extractionLooksWeak && canReExtract {
                ReExtractPill(isWorking: isReExtracting) {
                    Task { await reExtract() }
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    )
                )
            }
        }
        .task {
            warrantyMonthsText = purchase.primaryWarranty.map { String($0.durationMonths) } ?? ""
            returnDaysText = purchase.returnWindow.map { String($0.durationDays) } ?? ""
            priceText = purchase.price > 0 ? formatDecimal(purchase.price) : ""
            try? await Task.sleep(for: .milliseconds(280))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                showReExtractPill = true
            }
        }
        .onChange(of: purchase.itemName) { _, _ in
            Task { await CoverageNotificationScheduler.reschedule(for: purchase) }
        }
        .onChange(of: purchase.merchant) { _, _ in
            Task { await CoverageNotificationScheduler.reschedule(for: purchase) }
        }
        .onChange(of: extractionLooksWeak) { _, stillWeak in
            // After a successful re-extract that filled the gaps, retire
            // the pill with a spring so it doesn't hard-cut off screen.
            if !stillWeak {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    showReExtractPill = false
                }
            }
        }
        .sensoryFeedback(.success, trigger: reExtractTick)
        .fullScreenCover(isPresented: $isShowingFullImage) {
            if let data = purchase.receiptImage, let image = UIImage(data: data) {
                FullReceiptViewer(image: image)
            }
        }
    }

    // MARK: - Re-extract

    @MainActor
    private func reExtract() async {
        guard !isReExtracting, canReExtract else { return }
        isReExtracting = true
        defer { isReExtracting = false }

        // Prefer persisted OCR when we have it. Fall back to re-OCR from
        // the receipt image for older purchases stored before OCR
        // persistence landed.
        var lines: [RecognizedLine] = []
        if let data = purchase.ocrLinesData, let decoded = OCRLinePayload.decode(data) {
            lines = decoded
        } else if let data = purchase.receiptImage, let image = UIImage(data: data) {
            do {
                lines = try await VisionOCRService().recognize(in: image)
            } catch {
                return
            }
        }
        guard !lines.isEmpty else { return }

        let service = DefaultExtractionService()
        let proContext = ExtractionProContext.from(
            isPro: subscription.isPro,
            appUserID: subscription.appUserID
        )
        guard let receipt = try? await service.extract(from: lines, proContext: proContext) else { return }
        let extraction = ReceiptExtraction.from(
            receipt: receipt,
            confidences: nil,
            lineItems: []
        )

        apply(extraction: extraction)
        purchase.needsReextraction = false
        reExtractTick &+= 1

        // Re-sync the field bindings we own directly.
        warrantyMonthsText = purchase.primaryWarranty.map { String($0.durationMonths) } ?? warrantyMonthsText
        returnDaysText = purchase.returnWindow.map { String($0.durationDays) } ?? returnDaysText
        priceText = purchase.price > 0 ? formatDecimal(purchase.price) : priceText

        await CoverageNotificationScheduler.reschedule(for: purchase)
    }

    /// Fills blank fields on the purchase without ever overwriting a value
    /// the user has already committed to. Coverage terms go through
    /// `setDuration`/`setReturnWindow` with `byUser: false`, which the
    /// `.userProvided` guard blocks — so user-edited coverage is safe by
    /// construction.
    private func apply(extraction: ReceiptExtraction) {
        if purchase.merchant.trimmingCharacters(in: .whitespaces).isEmpty,
           let merchant = extraction.merchant.value {
            purchase.merchant = merchant
        }
        if purchase.itemName.trimmingCharacters(in: .whitespaces).isEmpty,
           let itemName = extraction.itemName.value {
            purchase.itemName = itemName
        }
        if purchase.price <= 0, let total = extraction.total.value {
            purchase.price = total
        }
        if purchase.currency.trimmingCharacters(in: .whitespaces).isEmpty,
           let currency = extraction.currency.value {
            purchase.currency = currency
        }
        if let coverage = extraction.coverage.value {
            switch coverage.kind {
            case .warranty:
                _ = purchase.setDuration(months: coverage.duration, byUser: false)
            case .returnWindow:
                _ = purchase.setReturnWindow(days: coverage.duration, byUser: false)
            }
        }
    }

    private var inferredChip: some View {
        Text("inferred")
            .font(KeptFont.sans(11, weight: .medium, relativeTo: .caption2))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var displayTitle: String {
        let trimmed = purchase.merchant.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "Receipt", comment: "Nav title fallback when the purchase has no merchant") : trimmed
    }

    private func recomputeExpiry() {
        if let warranty = purchase.primaryWarranty {
            _ = purchase.setDuration(
                months: warranty.durationMonths,
                byUser: warranty.source == .userProvided
            )
        }
        if let returnTerm = purchase.returnWindow {
            _ = purchase.setReturnWindow(
                days: returnTerm.durationDays,
                byUser: returnTerm.source == .userProvided
            )
        }
    }

    private func formatDecimal(_ value: Decimal) -> String {
        // POSIX, no grouping — avoids "2,849" → Decimal("2.849") on edit.
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

private struct FullReceiptViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Purchase.self, WarrantyTerm.self, PassRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let purchase = Purchase(
        merchant: "Primark",
        itemName: "Cargo Navy",
        price: 22,
        currency: "GBP",
        purchaseDate: .now
    )
    _ = purchase.setReturnWindow(days: 28, byUser: false)
    container.mainContext.insert(purchase)
    return NavigationStack {
        PurchaseDetailView(purchase: purchase)
    }
    .modelContainer(container)
}

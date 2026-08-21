import SwiftUI
import SwiftData

/// Fields + save bar for the extraction confirm screen. Renders inline —
/// the receipt image is drawn by the parent (see `CaptureView`) so the
/// scanning → confirm morph animates through a single shared image.
struct ExtractionConfirmView: View {
    /// Free tier item cap. See AGENTS.md / Monetisation.
    static let freeItemCap = 5

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionAccess.self) private var subscription

    /// Live count of stored purchases — used to enforce the free-tier cap
    /// AFTER scan succeeds (never before). Query is reactive so upgrading to
    /// Pro or deleting an item mid-flow immediately affects `canSave`.
    @Query private var storedPurchases: [Purchase]

    @State private var model: ExtractionConfirmModel
    @State private var savedTick = 0
    /// Set to `.capReached` when Save was blocked by the free cap. The paywall
    /// sheet listens on this via the isPresented binding.
    @State private var paywallReason: PaywallView.Reason?

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

    private enum ScrollAnchor: Hashable {
        case coverageCustom
    }

    var body: some View {
        ScrollViewReader { proxy in
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
            .sheet(item: Binding(
                get: { paywallReason.map(PaywallReasonBox.init) },
                set: { paywallReason = $0?.reason }
            )) { box in
                PaywallView(reason: box.reason)
                    .presentationDetents([.large])
            }
            // If the user completes purchase inside the paywall, isPro flips
            // to true reactively and we can auto-retry the save they were
            // trying to make. Only triggers when the sheet was open and now
            // isn't (i.e. paywallReason went nil) AND the user is now Pro.
            .onChange(of: subscription.isPro) { _, nowPro in
                if nowPro, paywallReason != nil {
                    paywallReason = nil
                    commitSave()
                }
            }
            .sensoryFeedback(.success, trigger: savedTick)
            .onChange(of: model.selectedCoveragePreset) { _, new in
                guard new == .custom else { return }
                // Wait a frame so the expander has laid out before we scroll.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(ScrollAnchor.coverageCustom, anchor: .bottom)
                    }
                }
            }
        }
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

            if !model.lineItems.isEmpty {
                lineItemsSection
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

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Items")
                    .font(KeptFont.sans(13, weight: .medium, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.addLineItem()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.keptTitle3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Add item")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xs)

            VStack(spacing: 0) {
                ForEach($model.lineItems) { $item in
                    lineItemRow(item: $item)
                    if item.id != model.lineItems.last?.id {
                        Divider().padding(.leading, Spacing.md)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private func lineItemRow(item: Binding<ReceiptLineItem>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            TextField("Item", text: item.name)
                .textInputAutocapitalization(.words)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField(
                "Price",
                value: item.price,
                format: .number.precision(.fractionLength(0...2))
            )
            .keyboardType(.decimalPad)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 68, maxWidth: 96)
            Button {
                model.removeLineItem(id: item.wrappedValue.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.wrappedValue.name)")
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
    }

    private var coverageRow: some View {
        row(.coverage, label: "Cover", extraCaption: model.coverageIsEstimated ? "Estimated" : nil) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                coverageChips
                if model.selectedCoveragePreset == .custom {
                    customCoverageEditor
                        .id(ScrollAnchor.coverageCustom)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: model.selectedCoveragePreset)
        }
    }

    private var coverageChips: some View {
        let columns = [GridItem(.adaptive(minimum: 108), spacing: Spacing.xs)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.xs) {
            ForEach(ExtractionConfirmModel.CoveragePreset.allCases, id: \.self) { preset in
                coverageChip(for: preset)
            }
        }
    }

    private func coverageChip(for preset: ExtractionConfirmModel.CoveragePreset) -> some View {
        let isSelected = model.selectedCoveragePreset == preset
        return Button {
            model.applyCoveragePreset(preset)
        } label: {
            Text(preset.label)
                .font(isSelected
                    ? KeptFont.sans(13, weight: .semibold, relativeTo: .footnote)
                    : KeptFont.sans(13, weight: .regular, relativeTo: .footnote))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(isSelected ? KeptColor.ink : Color(.tertiarySystemGroupedBackground))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var customCoverageEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Picker("", selection: $model.coverageKind) {
                Text("Warranty").tag(CoverageKind.warranty)
                Text("Return").tag(CoverageKind.returnWindow)
            }
            .pickerStyle(.segmented)
            .onChange(of: model.coverageKind) { _, _ in model.markTouched(.coverage) }

            HStack(spacing: Spacing.sm) {
                Button {
                    stepCustomDuration(by: -1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.keptTitle2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease")

                TextField("0", text: $model.coverageDurationText)
                    .keyboardType(.numberPad)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .font(.keptTitle3)
                    .frame(minWidth: 56, maxWidth: 80)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                    .onChange(of: model.coverageDurationText) { _, _ in model.markTouched(.coverage) }

                Button {
                    stepCustomDuration(by: 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.keptTitle2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase")

                Text(model.coverageKind == .warranty ? "months" : "days")
                    .font(.keptSubheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
        }
        .padding(.top, Spacing.xs)
    }

    private func stepCustomDuration(by delta: Int) {
        let current = Int(model.coverageDurationText) ?? 0
        let next = max(0, current + delta)
        model.coverageDurationText = next == 0 ? "" : String(next)
        model.markTouched(.coverage)
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
                    .font(KeptFont.sans(13, weight: .medium, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                content()
                    .font(.keptBody)
                if let caption {
                    Text(caption)
                        .font(.keptFootnote)
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
                    .font(.keptFootnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: save) {
                Text("Save receipt")
                    .font(.keptHeadline)
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
        // Free-tier cap: check AFTER scan succeeds (never before). Never
        // block the camera; the user has already invested effort scanning
        // and reviewing, so they see everything before hitting the wall.
        if !subscription.isPro,
           storedPurchases.count >= Self.freeItemCap {
            paywallReason = .capReached
            return
        }
        commitSave()
    }

    private func commitSave() {
        let purchase = model.save(into: modelContext)
        savedTick &+= 1
        Task { await CoverageNotificationScheduler.reschedule(for: purchase) }
        maybeRequestReview()
        if let onSave {
            onSave(purchase)
        } else {
            dismiss()
        }
    }

    /// After a milestone save, quietly ask iOS to consider showing the
    /// review prompt. iOS handles all throttling; we just point at the
    /// positive moment. Threshold set at 5 — user has clearly invested
    /// in the app by then. First save is too early (single-shot users
    /// haven't yet felt the value).
    @AppStorage("kept.lifetimeSaveCount") private var lifetimeSaveCount = 0
    private static let reviewSaveThreshold = 5

    private func maybeRequestReview() {
        lifetimeSaveCount &+= 1
        if lifetimeSaveCount == Self.reviewSaveThreshold {
            // Small delay so the confirm sheet finishes dismissing
            // before the review alert appears — stacked modals look bad.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                ReviewPrompter.request()
            }
        }
    }
}

/// Wrapper to make `PaywallView.Reason` Identifiable for `.sheet(item:)`.
private struct PaywallReasonBox: Identifiable {
    let reason: PaywallView.Reason
    var id: String {
        switch reason {
        case .capReached:     "capReached"
        case .firstPassAdded: "firstPassAdded"
        case .manual:         "manual"
        case .claimPack:      "claimPack"
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
    .environment(SubscriptionAccess(service: PreviewSubscriptionService(isPro: false)))
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
    .environment(SubscriptionAccess(service: PreviewSubscriptionService(isPro: false)))
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
    .environment(SubscriptionAccess(service: PreviewSubscriptionService(isPro: false)))
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

import SwiftUI
import SwiftData
#if DEBUG
import PhotosUI
#endif

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SubscriptionAccess.self) private var subscription
    @Query(sort: \Purchase.purchaseDate, order: .reverse) private var purchases: [Purchase]

    @AppStorage("libraryViewMode") private var viewModeRaw: String = LibraryViewMode.icons.rawValue
    /// Zoom navigation into purchase detail.
    @Namespace private var receiptNamespace
    /// Thumbnail morph between Icons / List / Gallery.
    @Namespace private var layoutNamespace

    @State private var isCapturing = false
    @State private var isSettingsPresented = false
    /// Set to true after a successful trial-boost grant so the celebration
    /// sheet appears once, then latches off via `TrialBoostEngagement.markGranted`.
    @State private var isTrialBoostCelebrationPresented = false
    @State private var isEvaluatingBoost = false
    /// Purchase to play the entry animation on (set from CaptureView.onSave,
    /// auto-cleared after the animation window elapses).
    @State private var justAddedPurchaseID: PersistentIdentifier?
    @State private var justAddedClearTask: Task<Void, Never>?
    /// Delete haptic trigger. Not debug-only — the sensoryFeedback
    /// modifier reads it in release too, so it lives outside the #if.
    @State private var deletedTick = 0
    #if DEBUG
    @State private var isPhotoPickerPresented = false
    @State private var isFixtureCapturePresented = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    #endif

    private var viewMode: LibraryViewMode {
        LibraryViewMode(rawValue: viewModeRaw) ?? .icons
    }

    private var viewModeBinding: Binding<LibraryViewMode> {
        Binding(
            get: { viewMode },
            set: { newValue in
                guard newValue != viewMode else { return }
                if reduceMotion {
                    viewModeRaw = newValue.rawValue
                } else {
                    withAnimation(.snappy(duration: 0.42, extraBounce: 0.04)) {
                        viewModeRaw = newValue.rawValue
                    }
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if purchases.isEmpty {
                    emptyState
                } else {
                    modeContent
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let issue = subscription.billingIssue {
                    BillingIssueBanner(issue: issue)
                        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.32),
                                   value: issue)
                }
            }
            .navigationTitle("Kept")  // stays for VoiceOver / back-button labelling
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Purchase.self) { purchase in
                PurchaseDetailView(purchase: purchase)
                    .navigationTransition(.zoom(sourceID: purchase.transitionID, in: receiptNamespace))
            }
            .task {
                await CoverageNotificationScheduler.rescheduleAll(purchases)
                await WeeklySummaryScheduler.reschedule(with: purchases)
            }
            .task(id: purchases.count) {
                await evaluateTrialBoost()
                await evaluateFreeCapNudge()
            }
            .task(id: subscription.billingIssue) {
                await evaluateBillingIssueNudge()
            }
            .task(id: subscription.proAccessExpiry) {
                await evaluateProAccessEndingNudge()
            }
            .sheet(isPresented: $isTrialBoostCelebrationPresented) {
                TrialBoostCelebration()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: deletedTick)
            .toolbar {
                // Principal placement replaces the text title with the
                // seal + wordmark lockup. Template rendering + .primary
                // foreground = auto-tints for light/dark mode.
                ToolbarItem(placement: .principal) {
                    Image("KeptLockup")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCapturing = true
                    } label: {
                        Label("Scan receipt", systemImage: "doc.viewfinder")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    viewModeMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                #if DEBUG
                ToolbarItem(placement: .secondaryAction) {
                    Menu("Debug") {
                        Button {
                            isFixtureCapturePresented = true
                        } label: {
                            Label("Capture OCR fixture", systemImage: "text.viewfinder")
                        }
                        Button {
                            // PhotosPicker inside Menu never presents — flip a flag instead.
                            isPhotoPickerPresented = true
                        } label: {
                            Label("Pick from Photos", systemImage: "photo.on.rectangle")
                        }
                        if !ReceiptFixtures.names.isEmpty {
                            Section("Fixtures") {
                                ForEach(ReceiptFixtures.names, id: \.self) { name in
                                    Button(name) {
                                        if let image = ReceiptFixtures.image(named: name) {
                                            pickedImage = image
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                #endif
            }
            .sheet(isPresented: $isCapturing) {
                CaptureView(onSave: flagNewlyAdded)
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
            }
            #if DEBUG
            .sheet(isPresented: $isFixtureCapturePresented) {
                FixtureCaptureView()
            }
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $pickerItem,
                matching: .images
            )
            .sheet(item: Binding(
                get: { pickedImage.map(IdentifiedImage.init) },
                set: { if $0 == nil { pickedImage = nil } }
            )) { wrapper in
                CaptureView(image: wrapper.image, onSave: flagNewlyAdded)
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pickedImage = image
                    }
                    pickerItem = nil
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch viewMode {
        case .icons:
            PurchaseGrid(
                purchases: purchases,
                zoomNamespace: receiptNamespace,
                layoutNamespace: layoutNamespace,
                highlightPurchaseID: justAddedPurchaseID,
                onDelete: delete(_:)
            )
        case .list:
            PurchaseList(
                purchases: purchases,
                zoomNamespace: receiptNamespace,
                layoutNamespace: layoutNamespace,
                onDelete: delete(_:)
            )
        case .gallery:
            PurchaseGallery(
                purchases: purchases,
                zoomNamespace: receiptNamespace,
                layoutNamespace: layoutNamespace,
                onDelete: delete(_:)
            )
        }
    }

    private var viewModeMenu: some View {
        Menu {
            Picker("View", selection: viewModeBinding) {
                ForEach(LibraryViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("View", systemImage: viewMode.systemImage)
        }
    }

    private var emptyState: some View {
        EmptyLibraryState(onScan: { isCapturing = true })
    }

    private func delete(_ purchase: Purchase) {
        CoverageNotificationScheduler.cancel(for: purchase)
        modelContext.delete(purchase)
        deletedTick &+= 1
    }

    /// Checks the engagement rules and, if they pass, calls Kept's Cloudflare
    /// Worker to grant 7 days of Pro via RevenueCat's REST API. On success
    /// marks the boost as granted (persisted so we don't re-trigger) and
    /// pops the celebration sheet. Failures are silent — the user just
    /// keeps their Free tier, no error banner to distract from what they
    /// were doing.
    private func evaluateTrialBoost() async {
        guard !isEvaluatingBoost else { return }
        guard TrialBoostEngagement.shouldGrant(
            purchaseCount: purchases.count,
            isPro: subscription.isPro
        ) else { return }
        isEvaluatingBoost = true
        defer { isEvaluatingBoost = false }
        do {
            try await subscription.grantTrialBoost()
            TrialBoostEngagement.markGranted()
            isTrialBoostCelebrationPresented = true
            await OfferNotificationScheduler.scheduleTrialBoostGrantedNudge()
        } catch {
            // Swallowed intentionally — the boost is a bonus, not a
            // guarantee. Next launch will re-evaluate if the user is still
            // eligible inside the 24-hour window.
        }
    }

    private func evaluateBillingIssueNudge() async {
        if let issue = subscription.billingIssue {
            await OfferNotificationScheduler.scheduleBillingIssueNudge(
                gracePeriodEndsAt: issue.gracePeriodEndsAt
            )
        } else {
            OfferNotificationScheduler.cancelBillingIssueNudge()
        }
    }

    private func evaluateProAccessEndingNudge() async {
        if let expiry = subscription.proAccessExpiry {
            await OfferNotificationScheduler.scheduleProAccessEndingNudge(
                endsAt: expiry.endsAt,
                reason: expiry.reason
            )
        } else {
            OfferNotificationScheduler.cancelProAccessEndingNudge()
        }
    }

    private func evaluateFreeCapNudge() async {
        // Fire when the user hits 4 saved receipts on the free tier — one
        // short of the current cap. Once-per-install, gated inside the
        // scheduler.
        guard !subscription.isPro, purchases.count == 4 else { return }
        await OfferNotificationScheduler.scheduleFreeCapApproachingNudge()
    }

    /// Flags a freshly-saved purchase so the grid can animate its entry.
    /// Clears after ~1.5s so a subsequent view refresh doesn't re-trigger.
    private func flagNewlyAdded(_ purchase: Purchase) {
        justAddedClearTask?.cancel()
        justAddedPurchaseID = purchase.persistentModelID
        justAddedClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            justAddedPurchaseID = nil
        }
    }

    #if DEBUG
    private struct IdentifiedImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }
    #endif
}

#Preview("Empty") {
    LibraryView()
        .modelContainer(for: [Purchase.self, WarrantyTerm.self, PassRecord.self], inMemory: true)
}

#Preview("With items") {
    let container = try! ModelContainer(
        for: Purchase.self, WarrantyTerm.self, PassRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let apple = Purchase(
        merchant: "Apple Chermside",
        itemName: "iPhone 16 Pro Max 1TB",
        price: 2849,
        currency: "AUD",
        purchaseDate: Calendar.current.date(byAdding: .day, value: -30, to: .now)!
    )
    _ = apple.setDuration(months: 12, byUser: false)
    apple.primaryWarranty?.confidence = 0.92
    context.insert(apple)

    let primark = Purchase(
        merchant: "Primark Stores Ltd",
        itemName: "Cargo Navy",
        price: 22,
        currency: "GBP",
        purchaseDate: Calendar.current.date(byAdding: .day, value: -400, to: .now)!
    )
    _ = primark.setReturnWindow(days: 28, byUser: false)
    primark.returnWindow?.confidence = 0.75
    context.insert(primark)

    let woolies = Purchase(
        merchant: "Woolworths",
        itemName: "Grocery shop",
        price: 87.42,
        currency: "AUD",
        purchaseDate: Calendar.current.date(byAdding: .day, value: -2, to: .now)!
    )
    context.insert(woolies)

    return LibraryView()
        .modelContainer(container)
}

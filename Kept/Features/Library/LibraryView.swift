import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SubscriptionAccess.self) private var subscription
    @Query(sort: \Purchase.purchaseDate, order: .reverse) private var purchases: [Purchase]

    /// Set by RootView when onboarding ended with "Yes, a few".
    var captureAfterOnboarding: Binding<Bool> = .constant(false)
    /// True while the front-door paywall cover is up, so capture waits.
    var paywallIsShowing: Bool = false
    /// Called after the first-save sheet dismisses, and when that sheet is
    /// skipped because the first save has no active warranty.
    var onFirstSaveMomentFinished: (OnboardingPaywallPolicy.Event) -> Bool = { _ in false }

    @AppStorage("libraryViewMode") private var viewModeRaw: String = LibraryViewMode.icons.rawValue
    /// Zoom navigation into purchase detail.
    @Namespace private var receiptNamespace
    /// Thumbnail morph between Icons / List / Gallery.
    @Namespace private var layoutNamespace

    /// Nil means no capture sheet. A nil image inside the request opens the camera.
    @State private var captureRequest: ReceiptCaptureRequest?
    @State private var isSettingsPresented = false
    /// Set to true after a successful trial-boost grant so the celebration
    /// alert fires once, then latches off via `TrialBoostEngagement.markGranted`.
    @State private var isTrialBoostAlertPresented = false
    @State private var isEvaluatingBoost = false
    /// Purchase to play the entry animation on (set from CaptureView.onSave,
    /// auto-cleared after the animation window elapses).
    @State private var justAddedPurchaseID: PersistentIdentifier?
    @State private var justAddedClearTask: Task<Void, Never>?
    /// Delete haptic trigger. Not debug-only — the sensoryFeedback
    /// modifier reads it in release too, so it lives outside the #if.
    @State private var deletedTick = 0
    @AppStorage(FirstSavePayoff.shownKey) private var hasShownFirstSavePayoff = false
    @State private var pendingPayoff: Purchase?
    @State private var payoffPurchase: Purchase?
    @State private var pendingPaywallWithoutSheet = false
    /// Trial-boost celebration waits until the payoff sheet (and the capture
    /// sheet that presents it) has closed.
    @State private var heldTrialBoostAlert = false
    /// Stops the existing-library migration from treating this session's own
    /// first save as a library that was already here.
    @State private var userDidSaveThisSession = false
    /// True only for the capture sheet that just saved, so dismissing
    /// without saving does not ask for notification permission.
    @State private var didSaveThisCapture = false
    /// The system notification prompt waits until the front-door paywall
    /// has dismissed, so the two never share the screen.
    @State private var notificationPromptWaitsForPaywall = false
    @State private var notificationPromptInFlight = false
    /// PhotosPicker inside a Menu never presents, so the toolbar flips this flag.
    @State private var isPhotoPickerPresented = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isPDFImporterPresented = false
    @State private var importFailureMessage: String?
    #if DEBUG
    @State private var isFixtureCapturePresented = false
    #endif

    private var isCapturing: Bool { captureRequest != nil }

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
            .animation(
                reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.32),
                value: purchases.isEmpty
            )
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
                await reconcileReminders(includingWeekly: true)
                stampExistingLibraryIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await reconcileReminders(includingWeekly: true) }
            }
            .onChange(of: reminderSyncToken) { _, _ in
                Task { await reconcileReminders(includingWeekly: false) }
            }
            .onChange(of: purchases.count) { _, _ in
                stampExistingLibraryIfNeeded()
            }
            .onChange(of: paywallIsShowing) { _, showing in
                if !showing {
                    releaseHeldTrialBoostAlert()
                    guard notificationPromptWaitsForPaywall else { return }
                    notificationPromptWaitsForPaywall = false
                    resolveNotificationPrompt(paywallWillPresent: false)
                }
            }
            .task(id: purchases.count) {
                await evaluateTrialBoost()
            }
            .task(id: subscription.billingIssue) {
                await evaluateBillingIssueNudge()
            }
            .task(id: subscription.proAccessExpiry) {
                await evaluateProAccessEndingNudge()
            }
            .alert(
                "Kept Pro unlocked for 7 days",
                isPresented: $isTrialBoostAlertPresented
            ) {
                Button("Continue", role: .cancel) {}
            } message: {
                Text("You've saved a few receipts already here's a week on us to see what the upgrade unlocks.")
            }
            .sensoryFeedback(.impact(weight: .light), trigger: deletedTick)
            .toolbar {
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
                    Menu {
                        Button(action: beginCameraCapture) {
                            Label("Scan receipt", systemImage: "doc.viewfinder")
                        }
                        Button {
                            // PhotosPicker inside Menu never presents — flip a flag instead.
                            isPhotoPickerPresented = true
                        } label: {
                            Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            isPDFImporterPresented = true
                        } label: {
                            Label("Import PDF", systemImage: "doc")
                        }
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
                            isPhotoPickerPresented = true
                        } label: {
                            Label("Pick from Photos", systemImage: "photo.on.rectangle")
                        }
                        if !ReceiptFixtures.names.isEmpty {
                            Section("Fixtures") {
                                ForEach(ReceiptFixtures.names, id: \.self) { name in
                                    Button(name) {
                                        if let image = ReceiptFixtures.image(named: name) {
                                            beginImportedCapture(image)
                                        }
                                    }
                                }
                            }
                        }
                        Section("Trial boost") {
                            Button {
                                // Preview the celebration alert without a
                                // real RC grant. Purely UI iteration.
                                isTrialBoostAlertPresented = true
                            } label: {
                                Label("Preview celebration alert", systemImage: "sparkles")
                            }
                            Button {
                                // Re-arm the flow: clear the "granted"
                                // latch and re-anchor first-launch to
                                // now so the next 3-receipt threshold
                                // triggers the real grant path.
                                TrialBoostEngagement.resetForDebug()
                            } label: {
                                Label("Reset engagement window", systemImage: "arrow.counterclockwise")
                            }
                            Button {
                                // Fire the OS-level celebration notification
                                // in 5 seconds — bypasses the 4-hour delay +
                                // once-per-install latch so you can actually
                                // see it in the notification centre while
                                // testing.
                                Task { await OfferNotificationScheduler.fireTrialBoostNudgeSoonForDebug() }
                            } label: {
                                Label("Fire boost notification in 5s", systemImage: "bell.badge")
                            }
                        }
                    }
                }
                #endif
            }
            .sheet(item: $captureRequest, onDismiss: handOffAfterCapture) { request in
                CaptureView(image: request.image, onSave: flagNewlyAdded)
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
            }
            .sheet(item: $payoffPurchase, onDismiss: {
                // The sheet is fully gone. The front-door gate is a cover
                // on the library, not a sheet stacked on this one.
                // Notification permission waits until that cover is gone too.
                let presentedPaywall = onFirstSaveMomentFinished(.firstSaveSheetDismissed)
                resolveNotificationPrompt(paywallWillPresent: presentedPaywall)
                scheduleTrialBoostRelease()
            }) { purchase in
                FirstSavePayoffSheet(purchase: purchase)
            }
            .sheet(isPresented: Binding(
                get: { captureAfterOnboarding.wrappedValue && !paywallIsShowing },
                set: { captureAfterOnboarding.wrappedValue = $0 }
            ), onDismiss: handOffAfterCapture) {
                CaptureView(onSave: flagNewlyAdded)
            }
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $photoPickerItem,
                matching: .images
            )
            .fileImporter(
                isPresented: $isPDFImporterPresented,
                allowedContentTypes: [UTType.pdf]
            ) { result in
                importPDF(from: result)
            }
            .onChange(of: photoPickerItem) { _, newItem in
                handleSelectedPhoto(newItem)
            }
            .alert(
                "Couldn't read that",
                isPresented: Binding(
                    get: { importFailureMessage != nil },
                    set: { if !$0 { importFailureMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: importFailureMessage ?? "")
            }
            #if DEBUG
            .sheet(isPresented: $isFixtureCapturePresented) {
                FixtureCaptureView()
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
        EmptyLibraryState(onScan: beginCameraCapture, photoPickerItem: $photoPickerItem)
    }

    private func beginCameraCapture() {
        captureRequest = .camera()
    }

    /// Same sheet, save callback, and dismiss hand-off as a camera scan.
    /// The free-tier cap still runs at save inside `ExtractionConfirmView`.
    private func beginImportedCapture(_ image: UIImage) {
        captureRequest = .imported(image)
    }

    private func handleSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            let outcome = await ReceiptImageImport.loadPhoto(item)
            if photoPickerItem == item {
                photoPickerItem = nil
            }
            switch outcome {
            case .ready(let image):
                beginImportedCapture(image)
            case .cancelled:
                break
            case .failed(let failure):
                showImportFailure(failure)
            }
        }
    }

    private func importPDF(from result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            // Current iOS does not call this on cancel. Older paths can.
            guard !ReceiptImageImport.isCancellation(error) else { return }
            showImportFailure(.unreadablePDF)
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                showImportFailure(.unreadablePDF)
                return
            }
            switch ReceiptImageImport.image(fromPDFData: data) {
            case .success(let image):
                beginImportedCapture(image)
            case .failure(let failure):
                showImportFailure(failure)
            }
        }
    }

    private func showImportFailure(_ failure: ReceiptImageImport.Failure) {
        importFailureMessage = failure.errorDescription
            ?? String(localized: "Couldn't read that image.")
    }

    private func delete(_ purchase: Purchase) {
        ReminderCoordinator.cancelExpiryReminders(for: purchase)
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
            presentTrialBoostAlert()
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

    /// Flags a freshly-saved purchase so the grid can animate its entry.
    /// Clears after ~1.5s so a subsequent view refresh doesn't re-trigger.
    /// The payoff sheet waits for capture to dismiss, and only if this
    /// purchase still has an active warranty.
    private func flagNewlyAdded(_ purchase: Purchase) {
        userDidSaveThisSession = true
        didSaveThisCapture = true
        justAddedClearTask?.cancel()
        justAddedPurchaseID = purchase.persistentModelID
        justAddedClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            justAddedPurchaseID = nil
        }

        let willShowSheet = FirstSavePayoff.isEligible(
            warrantyExpiry: purchase.primaryWarranty?.expiryDate,
            hasShown: hasShownFirstSavePayoff
        )
        if willShowSheet {
            pendingPayoff = purchase
            pendingPaywallWithoutSheet = false
        } else if FirstSavePayoff.shouldRequestPaywallWithoutSheet(
            previousCount: countBefore(purchase),
            newCount: countBefore(purchase) + 1,
            willShowSheet: false
        ) {
            pendingPaywallWithoutSheet = true
        }
    }

    private func countBefore(_ purchase: Purchase) -> Int {
        let alreadyListed = purchases.contains { $0.persistentModelID == purchase.persistentModelID }
        return alreadyListed ? max(0, purchases.count - 1) : purchases.count
    }

    /// Capture has finished dismissing. Present the payoff sheet, or the
    /// front-door paywall when the sheet does not apply. The notification
    /// prompt is not raised while either of those is on screen.
    private func handOffAfterCapture() {
        let saved = didSaveThisCapture
        didSaveThisCapture = false

        if let pending = pendingPayoff {
            payoffPurchase = pending
            pendingPayoff = nil
            return
        }
        if pendingPaywallWithoutSheet {
            pendingPaywallWithoutSheet = false
            let presentedPaywall = onFirstSaveMomentFinished(.firstSaveWithoutPayoffSheet)
            if saved {
                resolveNotificationPrompt(paywallWillPresent: presentedPaywall)
            }
            scheduleTrialBoostRelease()
            return
        }
        if saved {
            resolveNotificationPrompt(paywallWillPresent: false)
        }
        scheduleTrialBoostRelease()
    }

    /// Expiry end dates only, so typing a name does not reschedule.
    /// A CloudKit import that adds or edits a warranty changes this token.
    private var reminderSyncToken: String {
        purchases.map { purchase in
            let end = purchase.primaryWarranty?.expiryDate.timeIntervalSinceReferenceDate ?? -1
            return "\(purchase.persistentModelID)|\(end)"
        }.joined(separator: "\n")
    }

    private func reconcileReminders(includingWeekly: Bool) async {
        if includingWeekly {
            await ReminderCoordinator.reconcileOnForeground(modelContext: modelContext)
            let current = (try? modelContext.fetch(FetchDescriptor<Purchase>())) ?? purchases
            await WeeklySummaryScheduler.reschedule(with: current)
        } else {
            await ReminderCoordinator.reconcileFromContext(modelContext, rescheduleWeekly: false)
        }
    }

    private func resolveNotificationPrompt(paywallWillPresent: Bool) {
        switch NotificationPromptTiming.decision(
            hasAsked: NotificationPermissionPrompt.hasAsked,
            paywallWillPresent: paywallWillPresent
        ) {
        case .askNow:
            notificationPromptWaitsForPaywall = false
            askForNotificationPermissionIfNeeded()
        case .waitUntilPaywallDismisses:
            notificationPromptWaitsForPaywall = true
        case .skip:
            notificationPromptWaitsForPaywall = false
        }
    }

    /// Short pause so the payoff sheet or paywall cover can finish dismissing
    /// before the system alert appears.
    private func askForNotificationPermissionIfNeeded() {
        guard !notificationPromptInFlight else { return }
        guard !NotificationPermissionPrompt.hasAsked else { return }
        notificationPromptInFlight = true
        let context = modelContext
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            await NotificationPermissionPrompt.askIfNeededThenReconcile(modelContext: context)
            notificationPromptInFlight = false
        }
    }

    /// Libraries that already have purchases on appear never see the sheet.
    /// Skipped while a capture sheet is up so the user's own first save is
    /// not treated as an existing library.
    private func stampExistingLibraryIfNeeded() {
        guard !userDidSaveThisSession else { return }
        guard !isCapturing, !captureAfterOnboarding.wrappedValue else { return }
        guard pendingPayoff == nil, payoffPurchase == nil else { return }
        guard FirstSavePayoff.shouldStampExistingLibrary(
            hasShown: hasShownFirstSavePayoff,
            purchaseCount: purchases.count
        ) else { return }
        hasShownFirstSavePayoff = true
    }

    private func presentTrialBoostAlert() {
        if isCapturing || captureAfterOnboarding.wrappedValue || payoffPurchase != nil || pendingPayoff != nil {
            heldTrialBoostAlert = true
        } else {
            isTrialBoostAlertPresented = true
        }
    }

    /// The paywall cover is scheduled on the next run loop, so wait until
    /// that flag has landed before deciding the alert has a clear stage.
    private func scheduleTrialBoostRelease() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            releaseHeldTrialBoostAlert()
        }
    }

    private func releaseHeldTrialBoostAlert() {
        guard heldTrialBoostAlert else { return }
        guard payoffPurchase == nil, pendingPayoff == nil, !paywallIsShowing else { return }
        guard !isCapturing, !captureAfterOnboarding.wrappedValue else { return }
        heldTrialBoostAlert = false
        isTrialBoostAlertPresented = true
    }

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

import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var purchases: [Purchase]

    @AppStorage(SettingsKeys.expiryRemindersEnabled) private var expiryRemindersEnabled: Bool = SettingsDefaults.notificationsEnabled
    @AppStorage(SettingsKeys.weeklyReminderEnabled) private var weeklyReminderEnabled: Bool = SettingsDefaults.notificationsEnabled
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw: String = AppearancePreference.system.rawValue
    @AppStorage(SettingsKeys.darkAccent) private var darkAccentRaw: String = DarkAccentPreference.midnight.rawValue
    @AppStorage("kept.textSize") private var userTextSizeRaw: String = KeptTextSize.system.rawValue

    /// User's in-app text-size override. Applied to SettingsView because
    /// sheets present in their own environment and don't inherit the
    /// RootView-level `.keptTextSize(_:)` modifier — so without this,
    /// Settings would keep rendering at the system size even after the
    /// user changed it in-app.
    private var userTextSize: KeptTextSize {
        KeptTextSize(rawValue: userTextSizeRaw) ?? .system
    }

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var exportURL: URL?
    @State private var showDeleteConfirm = false
    @State private var showsPaywall = false

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    private var darkAccent: DarkAccentPreference {
        DarkAccentPreference(rawValue: darkAccentRaw) ?? .midnight
    }

    var body: some View {
        NavigationStack {
            Form {
                AccountSection(onUpgradeTapped: { showsPaywall = true })

                if authorizationStatus == .denied {
                    permissionDeniedSection
                }

                remindersSection
                notificationDebugSection
                appearanceSection
                languageSection
                AccessibilitySection()
                dataSection
                aboutSection
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView(reason: .manual)
            }
            .font(.keptBody)  // cascades to Text descendants inside Form
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .keptTextSize(userTextSize)
            .task {
                SettingsSnapshot.migrateReminderTogglesIfNeeded()
                await refreshAuthorizationStatus()
                refreshExportURL()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshAuthorizationStatus() }
            }
            .alert("Delete everything?", isPresented: $showDeleteConfirm) {
                Button("Delete all data", role: .destructive) {
                    deleteAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes every purchase and its reminders, including the weekly note. This can't be undone.")
            }
            .onChange(of: expiryRemindersEnabled) { _, enabled in
                Task { await handleExpiryToggle(enabled) }
            }
            .onChange(of: weeklyReminderEnabled) { _, enabled in
                Task { await handleWeeklyToggle(enabled) }
            }
        }
    }

    // MARK: - Sections

    private var permissionDeniedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Notifications are off", systemImage: "bell.slash.fill")
                    .font(.keptHeadline)
                    .foregroundStyle(.orange)
                Text("Kept can't warn you before coverage ends until you allow notifications in iOS Settings.")
                    .font(.keptFootnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                openSystemSettings()
            } label: {
                Label("Open Settings", systemImage: "arrow.up.right.square")
            }
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Expiry reminders", isOn: $expiryRemindersEnabled)
            Toggle("Weekly reminder", isOn: $weeklyReminderEnabled)
        } header: {
            Text("Reminders")
        } footer: {
            Text("Warranty reminders arrive 30 days and 7 days before cover ends, at 9:00. A return window is reminded 14 days before it closes, at 9:30. A weekly note arrives only after a week away, at 6:00 pm.")
        }
    }

    @ViewBuilder
    private var notificationDebugSection: some View {
        #if DEBUG
        Section {
            Button {
                Task { await ReminderCoordinator.fireExpiryPreview(purchases: purchases) }
            } label: {
                Label("Fire expiry reminder in 10s", systemImage: "bell")
                    .labelStyle(.settingsTile(tint: darkAccent.tint))
            }
            Button {
                Task { await ReminderCoordinator.fireWeeklyPreview() }
            } label: {
                Label("Fire weekly reminder in 10s", systemImage: "bell.badge")
                    .labelStyle(.settingsTile(tint: darkAccent.tint))
            }
        } header: {
            Text("Notification debug")
        } footer: {
            Text("Debug builds only. Background the app after tapping. Each fires in 10 seconds, and only if notifications are allowed.")
        }
        #else
        EmptyView()
        #endif
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(darkAccent.tint)
                        .frame(width: 29, height: 29)
                        .overlay {
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                    Text("Theme")
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(appearance.label) · \(darkAccent.label)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var languageSection: some View {
        Section {
            NavigationLink {
                LanguagePickerView()
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(darkAccent.tint)
                        .frame(width: 29, height: 29)
                        .overlay {
                            Image(systemName: "globe")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                    Text("Language")
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(currentLanguageDisplay)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var currentLanguageDisplay: String {
        let raw = UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? ""
        let language = AppLanguage(rawValue: raw) ?? .system
        if language == .system {
            let code = Bundle.main.preferredLocalizations.first ?? "en"
            return AppLanguage(rawValue: code)?.nativeName ?? "English"
        }
        return language.nativeName
    }

    private var dataSection: some View {
        Section {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export all data", systemImage: "square.and.arrow.up")
                        .labelStyle(.settingsTile(tint: darkAccent.tint))
                }
                .disabled(purchases.isEmpty)
            } else {
                Label("Export all data", systemImage: "square.and.arrow.up")
                    .labelStyle(.settingsTile(tint: darkAccent.tint))
                    .foregroundStyle(.secondary)
            }

            Button {
                resetOnboarding()
            } label: {
                Label("Reset onboarding", systemImage: "arrow.counterclockwise")
                    .labelStyle(.settingsTile(tint: darkAccent.tint))
            }

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete all data", systemImage: "trash")
                    .labelStyle(.settingsTile(tint: .red))
            }
            .disabled(purchases.isEmpty)
        } header: {
            Text("Data")
        } footer: {
            Text("\(purchases.count) items, synced with your iCloud", comment: "DESIGN-PENDING. Data section footer. Final wording is not locked. CloudKit sync is on for every signed-in account, including receipt photos. Needs plural handling on 'items'.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "\(appVersion) (\(buildNumber))")

            Link(destination: URL(string: "mailto:hello@getkept.xyz")!) {
                Label("Contact support", systemImage: "envelope")
                    .labelStyle(.settingsTile(tint: darkAccent.tint))
            }

            Link(destination: URL(string: "https://getkept.xyz/privacy")!) {
                Label("Privacy policy", systemImage: "hand.raised")
                    .labelStyle(.settingsTile(tint: darkAccent.tint))
            }
        }
    }

    // MARK: - Actions

    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func handleExpiryToggle(_ enabled: Bool) async {
        if enabled {
            await NotificationPermissionPrompt.requestFromSettingsIfUndetermined()
            await refreshAuthorizationStatus()
        }
        await syncReminderSchedules()
    }

    private func handleWeeklyToggle(_ enabled: Bool) async {
        if enabled {
            await NotificationPermissionPrompt.requestFromSettingsIfUndetermined()
            await refreshAuthorizationStatus()
        }
        await syncReminderSchedules()
    }

    private func syncReminderSchedules() async {
        let master = expiryRemindersEnabled || weeklyReminderEnabled
        SettingsSnapshot.setNotificationsMaster(enabled: master)
        await ReminderCoordinator.reconcile(purchases: purchases, rescheduleWeekly: false)
        await ReminderCoordinator.rescheduleWeeklyReminder()
    }

    private func refreshExportURL() {
        exportURL = generateExport()
    }

    private func generateExport() -> URL? {
        let export = KeptExport(
            exportedAt: .now,
            purchases: purchases.map(PurchaseExport.init)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(export) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kept-export-\(stamp).json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    private func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: SettingsKeys.hasOnboarded)
        UserDefaults.standard.set(false, forKey: SettingsKeys.hasSeenOnboardingPaywall)
        UserDefaults.standard.set(false, forKey: SettingsKeys.hasShownFirstSavePayoff)
        UserDefaults.standard.set(false, forKey: "settings.hasSeenFirstSavePayoff")
        NotificationPermissionPrompt.clearAskedFlag()
        dismiss()
    }

    private func deleteAll() {
        for purchase in purchases {
            ReminderCoordinator.cancelExpiryReminders(for: purchase)
            modelContext.delete(purchase)
        }
        ReminderCoordinator.cancelAllExpiryReminders()
        ReminderCoordinator.cancelWeeklyReminder()
        ReminderCoordinator.cancelLegacyWeeklySummary()
        try? modelContext.save()
        refreshExportURL()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Bundle info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Export payload

private struct KeptExport: Codable {
    let exportedAt: Date
    let purchases: [PurchaseExport]
}

private struct PurchaseExport: Codable {
    let merchant: String
    let itemName: String
    let price: Decimal
    let currency: String
    let purchaseDate: Date
    let notes: String
    let createdAt: Date
    let warranties: [WarrantyExport]
    let lineItems: [ReceiptLineItem]

    @MainActor
    init(_ purchase: Purchase) {
        self.merchant = purchase.merchant
        self.itemName = purchase.itemName
        self.price = purchase.price
        self.currency = purchase.currency
        self.purchaseDate = purchase.purchaseDate
        self.notes = purchase.notes
        self.createdAt = purchase.createdAt
        self.warranties = (purchase.warranties ?? []).map(WarrantyExport.init)
        self.lineItems = purchase.lineItems
    }
}

private struct WarrantyExport: Codable {
    let kind: String
    let source: String
    let confidence: Double
    let durationMonths: Int
    let durationDays: Int
    let expiryDate: Date

    @MainActor
    init(_ term: WarrantyTerm) {
        self.kind = term.kindRaw
        self.source = term.sourceRaw
        self.confidence = term.confidence
        self.durationMonths = term.durationMonths
        self.durationDays = term.durationDays
        self.expiryDate = term.expiryDate
    }
}

#Preview("Empty") {
    SettingsView()
        .modelContainer(for: [Purchase.self, WarrantyTerm.self, PassRecord.self], inMemory: true)
}

#Preview("With items") {
    let container = try! ModelContainer(
        for: Purchase.self, WarrantyTerm.self, PassRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext
    let apple = Purchase(
        merchant: "Apple",
        itemName: "iPhone 16 Pro",
        price: 1499,
        currency: "USD",
        purchaseDate: .now
    )
    _ = apple.setDuration(months: 12, byUser: false)
    ctx.insert(apple)
    return SettingsView()
        .modelContainer(container)
}

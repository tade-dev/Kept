import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var purchases: [Purchase]

    @AppStorage(SettingsKeys.notificationsEnabled) private var notificationsEnabled: Bool = SettingsDefaults.notificationsEnabled
    @AppStorage(SettingsKeys.leadDaysCSV) private var leadDaysCSV: String = "14"
    @AppStorage(SettingsKeys.notifyHour) private var notifyHour: Int = SettingsDefaults.notifyHour
    @AppStorage(SettingsKeys.notifyMinute) private var notifyMinute: Int = SettingsDefaults.notifyMinute
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

    private var leadDaysSet: Set<Int> {
        let ints = leadDaysCSV
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return ints.isEmpty ? SettingsDefaults.leadDays : Set(ints)
    }

    private func setLead(_ day: Int, on: Bool) {
        var set = leadDaysSet
        if on { set.insert(day) } else { set.remove(day) }
        if set.isEmpty { set = [day] }
        leadDaysCSV = set.sorted().map(String.init).joined(separator: ",")
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

    private var notifyTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = notifyHour
                comps.minute = notifyMinute
                return Calendar.current.date(from: comps) ?? .now
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                notifyHour = comps.hour ?? SettingsDefaults.notifyHour
                notifyMinute = comps.minute ?? SettingsDefaults.notifyMinute
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                AccountSection(onUpgradeTapped: { showsPaywall = true })

                if notificationsEnabled && authorizationStatus == .denied {
                    permissionDeniedSection
                }

                remindersSection
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
                await refreshAuthorizationStatus()
                refreshExportURL()
            }
            .alert("Delete everything?", isPresented: $showDeleteConfirm) {
                Button("Delete all data", role: .destructive) {
                    deleteAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes every purchase, warranty, and pending reminder. This can't be undone.")
            }
            .onChange(of: notificationsEnabled) { _, newValue in
                Task { await handleNotificationsToggle(newValue) }
            }
            .onChange(of: leadDaysCSV) { _, _ in
                Task { await rescheduleAll() }
            }
            .onChange(of: notifyHour) { _, _ in
                Task { await rescheduleAll() }
            }
            .onChange(of: notifyMinute) { _, _ in
                Task { await rescheduleAll() }
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
            Toggle("Notifications", isOn: $notificationsEnabled)

            if notificationsEnabled {
                ForEach(LeadDayOption.all, id: \.self) { day in
                    Toggle(
                        "\(day) days before",
                        isOn: Binding(
                            get: { leadDaysSet.contains(day) },
                            set: { setLead(day, on: $0) }
                        )
                    )
                }
                DatePicker(
                    "Time of day",
                    selection: notifyTimeBinding,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Reminders")
        } footer: {
            if notificationsEnabled {
                Text(reminderFooter)
            }
        }
    }

    private var reminderFooter: String {
        let sorted = leadDaysSet.sorted(by: >)
        let list = sorted.map(String.init).joined(separator: ", ")
        return String(
            localized: "Kept nudges you at \(list) days before any warranty or return window ends.",
            comment: "Reminder-lead-days summary in Settings footer; list is a pre-formatted number list. Needs plural handling on 'days'."
        )
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
            Text("\(purchases.count) items stored on this device.", comment: "Footer under Data section. Needs plural handling on 'items'.")
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

    private func handleNotificationsToggle(_ enabled: Bool) async {
        if enabled {
            _ = await CoverageNotificationScheduler.requestAuthorizationIfNeeded()
            await refreshAuthorizationStatus()
            await CoverageNotificationScheduler.rescheduleAll(purchases)
        } else {
            CoverageNotificationScheduler.cancelAll()
        }
    }

    private func rescheduleAll() async {
        guard notificationsEnabled else { return }
        await CoverageNotificationScheduler.rescheduleAll(purchases)
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
        dismiss()
    }

    private func deleteAll() {
        for purchase in purchases {
            CoverageNotificationScheduler.cancel(for: purchase)
            modelContext.delete(purchase)
        }
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

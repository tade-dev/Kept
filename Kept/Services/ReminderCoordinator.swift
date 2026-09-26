import Foundation
import SwiftData
import UserNotifications

/// Whether iOS will deliver a local notification we schedule.
/// Reading this never presents the system prompt.
enum NotificationAuthorization {
    enum Status: Equatable {
        case allowed
        case denied
        case notDetermined
    }

    static func status() async -> Status {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    static func isSchedulingAllowed() async -> Bool {
        await status() == .allowed
    }
}

/// The one system prompt, after the first save, plus the settings opt-in.
///
/// A denial or a failed request is latched. Later saves, launches, and
/// onboarding do not ask again.
enum NotificationPermissionPrompt {
    static let askedKey = "kept.hasAskedForNotificationPermission"

    static var hasAsked: Bool {
        UserDefaults.standard.bool(forKey: askedKey)
    }

    static func clearAskedFlag() {
        UserDefaults.standard.removeObject(forKey: askedKey)
    }

    /// Call only once the payoff sheet and the front-door paywall are gone.
    static func askIfNeededThenReconcile(modelContext: ModelContext) async {
        guard !hasAsked else { return }
        UserDefaults.standard.set(true, forKey: askedKey)

        let granted: Bool
        switch await NotificationAuthorization.status() {
        case .allowed:
            granted = true
        case .denied:
            granted = false
        case .notDetermined:
            granted = (try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )) ?? false
        }
        guard granted else { return }
        await ReminderCoordinator.reconcileFromContext(modelContext, rescheduleWeekly: true)
    }

    /// An explicit toggle in Settings. Never calls the system prompt after
    /// a denial, and does not ask when the status is already decided.
    static func requestFromSettingsIfUndetermined() async {
        guard await NotificationAuthorization.status() == .notDetermined else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )
    }
}

/// Wires purchases, settings, and authorization to the planner.
///
/// Save, edit, and delete update expiry reminders. Becoming active also
/// replaces the weekly note and rebuilds expiry reminders, which is how a
/// warranty edited on another device gets a local notification on this one.
enum ReminderCoordinator {
    static func reconcile(purchases: [Purchase], rescheduleWeekly: Bool) async {
        SettingsSnapshot.migrateReminderTogglesIfNeeded()
        let items = purchases.compactMap(ExpiryReminderItem.init(purchase:))
        let allowed = await NotificationAuthorization.isSchedulingAllowed()
        let planner = ReminderPlanner(now: .now, calendar: .current)
        let scheduler = ReminderNotificationScheduler(
            center: UNReminderNotificationCenter(),
            planner: planner
        )
        await scheduler.reconcileExpiry(
            items: items,
            enabled: SettingsSnapshot.expiryRemindersEnabled && allowed
        )
        if rescheduleWeekly {
            let lastOpen = Date()
            SettingsSnapshot.noteAppOpened(at: lastOpen)
            await scheduler.rescheduleWeekly(
                lastOpen: lastOpen,
                enabled: SettingsSnapshot.weeklyReminderEnabled && allowed
            )
        }
    }

    static func reconcileFromContext(_ context: ModelContext, rescheduleWeekly: Bool) async {
        let purchases = (try? context.fetch(FetchDescriptor<Purchase>())) ?? []
        await reconcile(purchases: purchases, rescheduleWeekly: rescheduleWeekly)
    }

    static func reconcileOnForeground(modelContext: ModelContext) async {
        await reconcileFromContext(modelContext, rescheduleWeekly: true)
    }

    /// Save and edit. Refreshes every warranty reminder so the 64-notification
    /// budget stays with the soonest end dates, without moving the weekly note.
    static func reschedule(purchase: Purchase) async {
        let all: [Purchase]
        if let context = purchase.modelContext {
            all = (try? context.fetch(FetchDescriptor<Purchase>())) ?? [purchase]
        } else {
            all = [purchase]
        }
        await reconcile(purchases: all, rescheduleWeekly: false)
    }

    static func rescheduleWeeklyReminder() async {
        let allowed = await NotificationAuthorization.isSchedulingAllowed()
        let planner = ReminderPlanner(now: .now, calendar: .current)
        let scheduler = ReminderNotificationScheduler(
            center: UNReminderNotificationCenter(),
            planner: planner
        )
        await scheduler.rescheduleWeekly(
            lastOpen: SettingsSnapshot.lastAppOpen,
            enabled: SettingsSnapshot.weeklyReminderEnabled && allowed
        )
    }

    static func cancelExpiryReminders(for purchase: Purchase) {
        cancelExpiryReminders(
            itemToken: ReminderPlanner.itemToken(
                forPersistentID: String(describing: purchase.persistentModelID)
            )
        )
    }

    static func cancelExpiryReminders(itemToken: String) {
        let identifiers = ReminderPlanner.expiryIdentifiers(forItemID: itemToken)
            + ReminderPlanner.legacyCoverageIdentifiers(forItemID: itemToken)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    static func cancelAllExpiryReminders() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.map(\.identifier).filter(ReminderPlanner.isManagedExpiryIdentifier)
            guard !identifiers.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    #if DEBUG
    /// Schedules a one-off banner in 10 seconds. Release builds do not
    /// include this. It does not replace the real 30- and 7-day requests.
    static func fireExpiryPreview(purchases: [Purchase]) async {
        guard await NotificationAuthorization.isSchedulingAllowed() else { return }
        let sample = purchases
            .compactMap(ExpiryReminderItem.init(purchase:))
            .sorted { $0.warrantyEnd < $1.warrantyEnd }
            .first
        await schedulePreview(
            identifier: "kept.debug.expiryReminder",
            title: ReminderCopy.expiryTitle,
            body: ReminderCopy.expiryBody(
                itemName: sample?.itemName ?? "Headphones",
                merchant: sample?.merchant ?? "Apple",
                leadDays: 7
            )
        )
    }

    static func fireWeeklyPreview() async {
        guard await NotificationAuthorization.isSchedulingAllowed() else { return }
        let index = WeeklyReminderCopy.index(for: .now, calendar: .current)
        await schedulePreview(
            identifier: "kept.debug.weeklyReminder",
            title: ReminderCopy.weeklyTitle,
            body: WeeklyReminderCopy.localizedLine(at: index)
        )
    }

    private static func schedulePreview(identifier: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
    #endif
}

extension ExpiryReminderItem {
    /// Latest warranty end on the purchase. Return windows are not included;
    /// a purchase with no warranty produces no expiry reminder.
    init?(purchase: Purchase) {
        let ends = (purchase.warranties ?? [])
            .filter { $0.kind == .warranty }
            .map(\.expiryDate)
        guard let warrantyEnd = ends.max() else { return nil }
        self.init(
            id: ReminderPlanner.itemToken(
                forPersistentID: String(describing: purchase.persistentModelID)
            ),
            itemName: purchase.itemName,
            merchant: purchase.merchant,
            warrantyEnd: warrantyEnd
        )
    }
}

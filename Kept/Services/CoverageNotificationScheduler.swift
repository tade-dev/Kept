import Foundation

/// Lead-window date helper kept for the original unit tests, and used by
/// `ReminderPlanner` for return-window alerts (14 days at 9:30, or a short
/// notice when that moment has already passed).
///
/// Warranty reminders (30 days and 7 days) and the weekly note are planned
/// by `ReminderPlanner` and applied by `ReminderCoordinator`. This type no
/// longer asks for notification permission; that happens once, after the
/// first save.
enum CoverageNotificationScheduler {
    static let defaultLeadDays = 14

    /// Pure fire-date helper — unit-tested.
    /// Returns `nil` when the term has already expired.
    /// If we're already inside the lead window, fires shortly so short return windows still warn.
    static func fireDate(
        expiry: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        leadDays: Int = defaultLeadDays,
        hour: Int = 9,
        minute: Int = 30
    ) -> Date? {
        guard expiry > now else { return nil }

        let ideal = calendar.date(byAdding: .day, value: -leadDays, to: expiry) ?? expiry
        let morningIdeal = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: ideal
        ) ?? ideal

        if morningIdeal > now {
            return morningIdeal
        }

        let soon = now.addingTimeInterval(30)
        return soon < expiry ? soon : nil
    }

    /// True when notifications may be scheduled. Does not present the system prompt.
    static func requestAuthorizationIfNeeded() async -> Bool {
        await NotificationAuthorization.isSchedulingAllowed()
    }

    /// Rebuild expiry reminders for the whole library. Does not move the weekly note.
    static func reschedule(for purchase: Purchase) async {
        await ReminderCoordinator.reschedule(purchase: purchase)
    }

    static func cancel(for purchase: Purchase) {
        ReminderCoordinator.cancelExpiryReminders(for: purchase)
    }

    /// Remove every pending warranty reminder, including older lead-day ids.
    static func cancelAll() {
        ReminderCoordinator.cancelAllExpiryReminders()
    }

    static func rescheduleAll(_ purchases: [Purchase]) async {
        await ReminderCoordinator.reconcile(purchases: purchases, rescheduleWeekly: false)
    }
}

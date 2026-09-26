import Foundation
import UserNotifications

/// The slice of `UNUserNotificationCenter` the scheduler needs.
/// Tests supply a stand-in; production uses `UNReminderNotificationCenter`.
protocol ReminderNotificationCenter {
    func pendingIdentifiers() async -> [String]
    func removePending(withIdentifiers identifiers: [String]) async
    func schedule(_ notifications: [PlannedLocalNotification], calendar: Calendar) async
}

struct UNReminderNotificationCenter: ReminderNotificationCenter {
    func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    func removePending(withIdentifiers identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func schedule(_ notifications: [PlannedLocalNotification], calendar: Calendar) async {
        let center = UNUserNotificationCenter.current()
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            if let leadDays = notification.leadDays {
                content.userInfo = ["leadDays": leadDays, "kind": "warrantyReminder"]
            } else {
                content.userInfo = ["kind": "weeklyReminder"]
            }
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: notification.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notification.identifier,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                // A missed reminder must not break save, edit, or launch.
            }
        }
    }
}

/// Applies a `ReminderPlanner` result to a notification center.
///
/// Adding a request with an identifier that is already pending replaces it.
/// Expiry reconcile also deletes identifiers that are no longer wanted,
/// including leftovers from the older lead-day scheduler.
struct ReminderNotificationScheduler {
    var center: any ReminderNotificationCenter
    var planner: ReminderPlanner

    func reconcileExpiry(items: [ExpiryReminderItem], enabled: Bool) async {
        let pending = await center.pendingIdentifiers()
        let foreignCount = pending.reduce(into: 0) { count, identifier in
            let reservedWeekly = identifier == ReminderPlanner.weeklyIdentifier
            if !ReminderPlanner.isManagedExpiryIdentifier(identifier), !reservedWeekly {
                count += 1
            }
        }
        let room = max(
            0,
            ReminderPlanner.systemPendingLimit - ReminderPlanner.weeklyReservedSlots - foreignCount
        )
        var capped = planner
        capped.expiryBudget = min(planner.expiryBudget, room)
        let desired = enabled ? capped.expiryNotifications(for: items) : []
        let desiredIDs = Set(desired.map(\.identifier))

        let stale = pending.filter { identifier in
            ReminderPlanner.isManagedExpiryIdentifier(identifier) && !desiredIDs.contains(identifier)
        }
        if !stale.isEmpty {
            await center.removePending(withIdentifiers: stale)
        }
        // Remove-then-add so an edited end date replaces the pending request
        // instead of leaving the previous fire date in place.
        let replacements = desired.map(\.identifier)
        if !replacements.isEmpty {
            await center.removePending(withIdentifiers: replacements)
        }
        await center.schedule(desired, calendar: capped.calendar)
    }

    /// One weekly request. The same identifier is removed before the new
    /// date is added, including when the reminder is turned off.
    func rescheduleWeekly(lastOpen: Date, enabled: Bool) async {
        await center.removePending(withIdentifiers: [ReminderPlanner.weeklyIdentifier])
        guard enabled else { return }
        let notification = planner.weeklyNotification(lastOpen: lastOpen)
        await center.schedule([notification], calendar: planner.calendar)
    }
}

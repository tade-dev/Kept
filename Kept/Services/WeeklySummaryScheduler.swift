import Foundation
import UserNotifications

/// Schedules one weekly local notification — the Sunday-morning summary
/// of the user's coverage state. Reinforces Kept's core promise ("we
/// remember for you") without asking anything of them.
///
/// Rules:
/// - Fires Sundays at 10:00 local time, repeats weekly.
/// - Only if the user has completed onboarding, enabled notifications,
///   and has at least `minItemsForSummary` items in their library —
///   a user with one receipt doesn't need a weekly summary.
/// - Recomputed on every `reschedule(...)` call so the copy reflects
///   the current library snapshot. Idempotent per identifier.
///
/// Kept intentionally does NOT ship "come back" nudges. See the brand
/// brief — Kept is the quiet-trust app, not the streak app.
enum WeeklySummaryScheduler {
    /// Single stable identifier so re-scheduling replaces the pending
    /// request instead of stacking.
    private static let identifier = "kept.weeklySummary"
    private static let minItemsForSummary = 3
    private static let fireHour = 10
    private static let fireMinute = 0
    private static let fireWeekday = 1  // Calendar's Sunday

    /// Recompute + reschedule with the latest snapshot. Called on
    /// foreground and after any library mutation.
    static func reschedule(with purchases: [Purchase]) async {
        guard SettingsSnapshot.hasOnboarded else { return }
        guard SettingsSnapshot.notificationsEnabled else {
            cancel()
            return
        }
        guard purchases.count >= minItemsForSummary else {
            cancel()
            return
        }
        guard await CoverageNotificationScheduler.requestAuthorizationIfNeeded() else {
            return
        }

        let snapshot = summarise(purchases: purchases)
        let content = UNMutableNotificationContent()
        content.title = "Your Kept summary"
        content.body = snapshot
        content.sound = .default
        content.userInfo = ["kind": "weeklySummary"]

        var components = DateComponents()
        components.weekday = fireWeekday
        components.hour = fireHour
        components.minute = fireMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try? await center.add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - Copy

    /// Builds a factual, calm summary. Avoids marketing voice ("Great
    /// news!", exclamation marks) — matches the brand brief's "quiet
    /// adult" tone.
    private static func summarise(purchases: [Purchase]) -> String {
        let items = purchases.count

        let upcomingTerms = purchases
            .flatMap { $0.warranties ?? [] }
            .filter { $0.expiryDate > .now }
            .sorted { $0.expiryDate < $1.expiryDate }

        guard let next = upcomingTerms.first else {
            return "\(items) items in your library. Nothing expiring soon."
        }

        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: next.expiryDate)
        ).day ?? 0

        let itemName = next.purchase?.itemName.trimmingCharacters(in: .whitespaces)
        let subject = (itemName?.isEmpty == false ? itemName! : "an item")

        if days <= 0 {
            return "\(items) items covered. \(subject) expires today."
        }
        if days == 1 {
            return "\(items) items covered. \(subject) expires tomorrow."
        }
        return "\(items) items covered. Next expiry: \(subject) in \(days) days."
    }
}

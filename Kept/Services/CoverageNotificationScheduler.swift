import Foundation
import SwiftData
import UserNotifications

/// Schedules local alerts at coverage expiry minus 14 days.
enum CoverageNotificationScheduler {
    static let leadDays = 14
    private static let idPrefix = "kept.coverage."

    /// Pure fire-date helper — unit-tested.
    /// Returns `nil` when the term has already expired.
    /// If we're already inside the 14-day window, fires shortly so short return windows still warn.
    static func fireDate(
        expiry: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard expiry > now else { return nil }

        let ideal = calendar.date(byAdding: .day, value: -leadDays, to: expiry) ?? expiry
        // Prefer mid-morning local so it doesn't fire at midnight.
        let morningIdeal = calendar.date(
            bySettingHour: 9,
            minute: 30,
            second: 0,
            of: ideal
        ) ?? ideal

        if morningIdeal > now {
            return morningIdeal
        }

        // Inside the lead window — nudge soon, still before expiry.
        let soon = now.addingTimeInterval(30)
        return soon < expiry ? soon : nil
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Cancel existing requests for this purchase and schedule one per upcoming term.
    static func reschedule(for purchase: Purchase) async {
        cancel(for: purchase)

        let terms = (purchase.warranties ?? []).filter { $0.expiryDate > .now }
        guard !terms.isEmpty else { return }

        guard await requestAuthorizationIfNeeded() else { return }

        let item = displayName(purchase.itemName, fallback: "your purchase")
        let merchant = displayName(purchase.merchant, fallback: nil)
        let token = purchaseToken(purchase)

        for term in terms {
            guard let fire = fireDate(expiry: term.expiryDate) else { continue }

            // Copy reflects remaining days *when the alert fires*, not when we schedule.
            let daysLeft = max(
                1,
                Calendar.current.dateComponents(
                    [.day],
                    from: Calendar.current.startOfDay(for: fire),
                    to: Calendar.current.startOfDay(for: term.expiryDate)
                ).day ?? leadDays
            )

            let content = UNMutableNotificationContent()
            content.sound = .default
            content.title = term.kind == .returnWindow ? "Return window ending" : "Warranty ending"
            content.body = body(
                kind: term.kind,
                item: item,
                merchant: merchant,
                daysLeft: daysLeft
            )
            content.userInfo = [
                "purchaseToken": token,
                "kind": term.kind.rawValue,
            ]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fire
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: requestID(token: token, kind: term.kind),
                content: content,
                trigger: trigger
            )

            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                // Best-effort — missing a reminder must not break save/edit.
            }
        }
    }

    static func cancel(for purchase: Purchase) {
        let token = purchaseToken(purchase)
        let ids = CoverageKind.allCases.map { requestID(token: token, kind: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func rescheduleAll(_ purchases: [Purchase]) async {
        _ = await requestAuthorizationIfNeeded()
        for purchase in purchases {
            await reschedule(for: purchase)
        }
    }

    // MARK: - Helpers

    private static func requestID(token: String, kind: CoverageKind) -> String {
        "\(idPrefix)\(token).\(kind.rawValue)"
    }

    private static func purchaseToken(_ purchase: Purchase) -> String {
        // Stable for the life of the SwiftData row; short enough for UN identifiers.
        let raw = String(describing: purchase.persistentModelID)
        let digest = raw.utf8.reduce(into: UInt64(1469598103934665603)) { hash, byte in
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(digest, radix: 16)
    }

    private static func displayName(_ value: String, fallback: String?) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback ?? "" }
        return trimmed
    }

    private static func body(
        kind: CoverageKind,
        item: String,
        merchant: String?,
        daysLeft: Int
    ) -> String {
        let dayWord = daysLeft == 1 ? "day" : "days"
        switch kind {
        case .returnWindow:
            if let merchant, !merchant.isEmpty {
                return "\(item) from \(merchant) — return window ends in \(daysLeft) \(dayWord)."
            }
            return "\(item) — return window ends in \(daysLeft) \(dayWord)."
        case .warranty:
            if let merchant, !merchant.isEmpty {
                return "Warranty on \(item) from \(merchant) ends in \(daysLeft) \(dayWord)."
            }
            return "Warranty on \(item) ends in \(daysLeft) \(dayWord)."
        }
    }
}

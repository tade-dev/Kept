import Foundation
import SwiftData
import UserNotifications

/// Schedules local alerts at coverage expiry minus the user's chosen lead window.
enum CoverageNotificationScheduler {
    static let defaultLeadDays = 14
    private static let idPrefix = "kept.coverage."

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

    /// Cancel existing requests for this purchase and schedule one per (upcoming term × lead day).
    static func reschedule(for purchase: Purchase) async {
        cancel(for: purchase)

        // Never prompt for auth before the user reaches the onboarding step that frames the ask.
        guard SettingsSnapshot.hasOnboarded else { return }
        guard SettingsSnapshot.notificationsEnabled else { return }

        let terms = (purchase.warranties ?? []).filter { $0.expiryDate > .now }
        guard !terms.isEmpty else { return }

        guard await requestAuthorizationIfNeeded() else { return }

        let item = displayName(purchase.itemName, fallback: "your purchase")
        let merchant = displayName(purchase.merchant, fallback: nil)
        let token = purchaseToken(purchase)
        let leads = SettingsSnapshot.leadDaysSet.sorted(by: >)
        let hour = SettingsSnapshot.notifyHour
        let minute = SettingsSnapshot.notifyMinute

        for term in terms {
            for lead in leads {
                guard let fire = fireDate(
                    expiry: term.expiryDate,
                    leadDays: lead,
                    hour: hour,
                    minute: minute
                ) else { continue }

                let daysLeft = max(
                    1,
                    Calendar.current.dateComponents(
                        [.day],
                        from: Calendar.current.startOfDay(for: fire),
                        to: Calendar.current.startOfDay(for: term.expiryDate)
                    ).day ?? lead
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
                    "leadDays": lead,
                ]

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: fire
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: requestID(token: token, kind: term.kind, leadDays: lead),
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
    }

    static func cancel(for purchase: Purchase) {
        let token = purchaseToken(purchase)
        var ids: [String] = []
        for kind in CoverageKind.allCases {
            for lead in LeadDayOption.all {
                ids.append(requestID(token: token, kind: kind, leadDays: lead))
            }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Nuke every Kept-scheduled request. Used when the user disables notifications.
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(idPrefix) }
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    static func rescheduleAll(_ purchases: [Purchase]) async {
        // Same guard as `reschedule(for:)` — no cold system prompt before onboarding.
        guard SettingsSnapshot.hasOnboarded else { return }
        guard SettingsSnapshot.notificationsEnabled else {
            cancelAll()
            return
        }
        _ = await requestAuthorizationIfNeeded()
        for purchase in purchases {
            await reschedule(for: purchase)
        }
    }

    // MARK: - Helpers

    private static func requestID(token: String, kind: CoverageKind, leadDays: Int) -> String {
        "\(idPrefix)\(token).\(kind.rawValue).\(leadDays)"
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

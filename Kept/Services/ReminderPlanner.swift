import Foundation

/// One purchase Kept may remind the user about. The id is stable for the
/// life of the local SwiftData row (see `ReminderPlanner.itemToken`).
/// A row can have a warranty end, a return-window end, or both.
struct ExpiryReminderItem: Equatable {
    var id: String
    var itemName: String
    var merchant: String
    var warrantyEnd: Date? = nil
    var returnEnd: Date? = nil
}

/// A local notification the scheduler can hand to `UNUserNotificationCenter`
/// without this type knowing about that API.
struct PlannedLocalNotification: Equatable {
    var identifier: String
    var title: String
    var body: String
    var fireDate: Date
    var leadDays: Int?
    /// `warrantyExpiry`, `returnWindow`, or `weeklyReminder`.
    var kind: String = "warrantyExpiry"
}

/// When the one-time system notification prompt may appear.
///
/// The first-save payoff sheet comes first. The front-door paywall, if it
/// is going to show, comes next. The system alert waits until both are gone
/// so it never covers either one. A denial is not asked again.
enum NotificationPromptTiming: Equatable {
    case askNow
    case waitUntilPaywallDismisses
    case skip

    static func decision(hasAsked: Bool, paywallWillPresent: Bool) -> NotificationPromptTiming {
        guard !hasAsked else { return .skip }
        if paywallWillPresent { return .waitUntilPaywallDismisses }
        return .askNow
    }
}

/// Pure date and copy planning for warranty reminders, return-window
/// alerts, and the weekly note.
///
/// `now` and `calendar` are injected so tests can pin a time zone, including
/// a daylight-saving transition, without talking to `UNUserNotificationCenter`.
struct ReminderPlanner {
    var now: Date
    var calendar: Calendar
    var expiryHour: Int = 9
    var expiryMinute: Int = 0
    var weeklyHour: Int = 18
    var weeklyMinute: Int = 0
    var leadDays: [Int] = [30, 7]
    /// How many expiry notifications may be pending. Defaults to 63 so one
    /// of iOS's 64 slots stays free for the weekly reminder. The scheduler
    /// lowers this further when other Kept notifications are already pending.
    var expiryBudget: Int = ReminderPlanner.defaultExpiryBudget

    static let systemPendingLimit = 64
    static let weeklyReservedSlots = 1
    static let defaultExpiryBudget = systemPendingLimit - weeklyReservedSlots

    static let expiryIdentifierPrefix = "kept.warranty."
    static let legacyCoveragePrefix = "kept.coverage."
    static let weeklyIdentifier = "kept.weeklyReminder"
    /// Sunday summary removed in favour of the weekly note. Reconcile
    /// cancels this id from both the pending and delivered lists.
    static let legacyWeeklySummaryIdentifier = "kept.weeklySummary"
    /// Previous default lead and clock time for a return window.
    /// Warranty alerts stay on the fixed 30- and 7-day, 9:00 schedule.
    static let returnWindowLeadDays = 14
    static let returnWindowHour = 9
    static let returnWindowMinute = 30

    static func expiryIdentifier(itemID: String, leadDays: Int) -> String {
        "\(expiryIdentifierPrefix)\(itemID).\(leadDays)"
    }

    static func expiryIdentifiers(forItemID itemID: String, leadDays: [Int] = [30, 7]) -> [String] {
        leadDays.map { expiryIdentifier(itemID: itemID, leadDays: $0) }
    }

    /// Same identifier the old scheduler used for the default 14-day return alert.
    static func returnWindowIdentifier(itemID: String) -> String {
        "\(legacyCoveragePrefix)\(itemID).returnWindow.\(returnWindowLeadDays)"
    }

    /// Identifiers the previous lead-day scheduler used for this row, so a
    /// reconcile can remove them instead of leaving stale requests behind.
    static func legacyCoverageIdentifiers(forItemID itemID: String) -> [String] {
        let kinds = ["warranty", "returnWindow"]
        let leads = [7, 14, 30]
        return kinds.flatMap { kind in
            leads.map { lead in "\(legacyCoveragePrefix)\(itemID).\(kind).\(lead)" }
        }
    }

    static func isManagedExpiryIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(expiryIdentifierPrefix) || identifier.hasPrefix(legacyCoveragePrefix)
    }

    /// Same FNV-1a digest the original coverage scheduler used, so legacy
    /// identifiers still match the row after this change.
    static func itemToken(forPersistentID raw: String) -> String {
        let digest = raw.utf8.reduce(into: UInt64(1_469_598_103_934_665_603)) { hash, byte in
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(digest, radix: 16)
    }

    /// 9:00 local on the calendar day `leadDays` before `expiry`.
    /// Returns nil when that instant is already in the past, or would fall
    /// on or after the warranty has ended.
    func triggerDate(expiry: Date, leadDays: Int) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: -leadDays, to: expiry) else { return nil }
        guard let fire = Self.wallClock(day, hour: expiryHour, minute: expiryMinute, calendar: calendar) else {
            return nil
        }
        guard fire > now, fire < expiry else { return nil }
        return fire
    }

    /// 9:30 local, `returnWindowLeadDays` before the return end.
    /// If that moment has already passed and the window is still open, the
    /// old scheduler's short-notice fire (about 30 seconds out) is used.
    func returnWindowFireDate(expiry: Date) -> Date? {
        CoverageNotificationScheduler.fireDate(
            expiry: expiry,
            now: now,
            calendar: calendar,
            leadDays: Self.returnWindowLeadDays,
            hour: Self.returnWindowHour,
            minute: Self.returnWindowMinute
        )
    }

    /// Soonest warranty and return-window reminders first, capped at `expiryBudget`.
    func expiryNotifications(for items: [ExpiryReminderItem]) -> [PlannedLocalNotification] {
        var planned: [PlannedLocalNotification] = []
        planned.reserveCapacity(items.count * (leadDays.count + 1))
        for item in items {
            if let warrantyEnd = item.warrantyEnd {
                for lead in leadDays {
                    guard let fire = triggerDate(expiry: warrantyEnd, leadDays: lead) else { continue }
                    planned.append(
                        PlannedLocalNotification(
                            identifier: Self.expiryIdentifier(itemID: item.id, leadDays: lead),
                            title: ReminderCopy.expiryTitle,
                            body: ReminderCopy.expiryBody(
                                itemName: item.itemName,
                                merchant: item.merchant,
                                leadDays: lead
                            ),
                            fireDate: fire,
                            leadDays: lead,
                            kind: "warrantyExpiry"
                        )
                    )
                }
            }
            if let returnEnd = item.returnEnd, let fire = returnWindowFireDate(expiry: returnEnd) {
                let daysLeft = returnWindowDaysLeft(fire: fire, expiry: returnEnd)
                planned.append(
                    PlannedLocalNotification(
                        identifier: Self.returnWindowIdentifier(itemID: item.id),
                        title: ReminderCopy.returnWindowTitle,
                        body: ReminderCopy.returnWindowBody(
                            itemName: item.itemName,
                            merchant: item.merchant,
                            daysLeft: daysLeft
                        ),
                        fireDate: fire,
                        leadDays: Self.returnWindowLeadDays,
                        kind: "returnWindow"
                    )
                )
            }
        }
        planned.sort { lhs, rhs in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.identifier < rhs.identifier
        }
        let budget = max(0, expiryBudget)
        if planned.count > budget {
            return Array(planned.prefix(budget))
        }
        return planned
    }

    /// Whole calendar days from the fire date to the return end, at least 1.
    /// Matches the old scheduler's copy, which never said "0 days".
    func returnWindowDaysLeft(fire: Date, expiry: Date) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: fire),
            to: calendar.startOfDay(for: expiry)
        ).day ?? Self.returnWindowLeadDays
        return max(1, days)
    }

    /// 6:00 pm local, seven calendar days after `lastOpen`.
    /// If that instant has already passed (a stale last-open), the next
    /// 6:00 pm at least seven days from `now` is used instead.
    func weeklyFireDate(lastOpen: Date) -> Date {
        let shifted = calendar.date(byAdding: .day, value: 7, to: lastOpen)
            ?? lastOpen.addingTimeInterval(7 * 24 * 60 * 60)
        var fire = Self.wallClock(shifted, hour: weeklyHour, minute: weeklyMinute, calendar: calendar) ?? shifted
        if fire <= now {
            let fromNow = calendar.date(byAdding: .day, value: 7, to: now)
                ?? now.addingTimeInterval(7 * 24 * 60 * 60)
            fire = Self.wallClock(fromNow, hour: weeklyHour, minute: weeklyMinute, calendar: calendar) ?? fromNow
        }
        if fire <= now {
            let next = calendar.date(byAdding: .day, value: 1, to: fire)
                ?? fire.addingTimeInterval(24 * 60 * 60)
            fire = Self.wallClock(next, hour: weeklyHour, minute: weeklyMinute, calendar: calendar) ?? next
        }
        return fire
    }

    func weeklyNotification(lastOpen: Date) -> PlannedLocalNotification {
        let index = WeeklyReminderCopy.index(for: lastOpen, calendar: calendar)
        return PlannedLocalNotification(
            identifier: Self.weeklyIdentifier,
            title: ReminderCopy.weeklyTitle,
            body: WeeklyReminderCopy.localizedLine(at: index),
            fireDate: weeklyFireDate(lastOpen: lastOpen),
            leadDays: nil,
            kind: "weeklyReminder"
        )
    }

    static func wallClock(_ date: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        parts.nanosecond = 0
        parts.timeZone = calendar.timeZone
        return calendar.date(from: parts)
    }
}

enum ReminderCopy {
    static var expiryTitle: String {
        String(localized: "Warranty reminder", comment: "Title of a local notification before a warranty ends")
    }

    static var weeklyTitle: String {
        String(localized: "A note from Kept", comment: "Title of the gentle weekly reminder")
    }

    static func expiryBody(itemName: String, merchant: String, leadDays: Int) -> String {
        let item = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let shop = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemText = item.isEmpty
            ? String(localized: "your purchase", comment: "Fallback item name in a warranty reminder")
            : item
        if shop.isEmpty {
            return String(
                localized: "Warranty on \(itemText) ends in \(leadDays) days.",
                comment: "Warranty reminder without a merchant. leadDays is 30 or 7."
            )
        }
        return String(
            localized: "Warranty on \(itemText) from \(shop) ends in \(leadDays) days.",
            comment: "Warranty reminder naming the item and merchant. leadDays is 30 or 7."
        )
    }

    static var returnWindowTitle: String {
        String(localized: "Return window ending", comment: "Title of a local notification before a return window ends")
    }

    /// Same sentences the previous scheduler used. `daysLeft` is at least 1.
    static func returnWindowBody(itemName: String, merchant: String, daysLeft: Int) -> String {
        let item = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let shop = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemText = item.isEmpty
            ? String(localized: "your purchase", comment: "Fallback item name in a return-window reminder")
            : item
        if daysLeft == 1 {
            if shop.isEmpty {
                return String(
                    localized: "\(itemText) — return window ends in 1 day.",
                    comment: "Return-window reminder without a merchant, one day left"
                )
            }
            return String(
                localized: "\(itemText) from \(shop) — return window ends in 1 day.",
                comment: "Return-window reminder naming the item and merchant, one day left"
            )
        }
        if shop.isEmpty {
            return String(
                localized: "\(itemText) — return window ends in \(daysLeft) days.",
                comment: "Return-window reminder without a merchant"
            )
        }
        return String(
            localized: "\(itemText) from \(shop) — return window ends in \(daysLeft) days.",
            comment: "Return-window reminder naming the item and merchant"
        )
    }
}

/// Short lines for the weekly note. Rotation is by the calendar day of the
/// last open, so rescheduling on the same day keeps the same line.
enum WeeklyReminderCopy {
    static let lines: [String] = [
        "Bought anything this week? Snap the receipt before it fades.",
        "A receipt is easier to keep now than to find later.",
        "New purchase this week? Add it while the details are still clear.",
        "If something new came home, a photo of the receipt is enough.",
        "Warranty dates are easier to keep once the receipt is in Kept.",
    ]

    static func line(at index: Int) -> String {
        lines[normalized(index)]
    }

    /// Localized form of `line(at:)`. Literals stay in source so the string
    /// catalog can extract them.
    static func localizedLine(at index: Int) -> String {
        switch normalized(index) {
        case 0:
            String(
                localized: "Bought anything this week? Snap the receipt before it fades.",
                comment: "Weekly reminder. Calm, no guilt."
            )
        case 1:
            String(
                localized: "A receipt is easier to keep now than to find later.",
                comment: "Weekly reminder. Calm, no guilt."
            )
        case 2:
            String(
                localized: "New purchase this week? Add it while the details are still clear.",
                comment: "Weekly reminder. Calm, no guilt."
            )
        case 3:
            String(
                localized: "If something new came home, a photo of the receipt is enough.",
                comment: "Weekly reminder. Calm, no guilt."
            )
        default:
            String(
                localized: "Warranty dates are easier to keep once the receipt is in Kept.",
                comment: "Weekly reminder. Calm, no guilt."
            )
        }
    }

    static func index(for date: Date, calendar: Calendar) -> Int {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return normalized(day)
    }

    private static func normalized(_ index: Int) -> Int {
        let count = lines.count
        let remainder = index % count
        return remainder >= 0 ? remainder : remainder + count
    }
}

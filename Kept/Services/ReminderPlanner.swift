import Foundation

/// One warranty Kept may remind the user about. The id is stable for the
/// life of the local SwiftData row (see `ReminderPlanner.itemToken`).
struct ExpiryReminderItem: Equatable {
    var id: String
    var itemName: String
    var merchant: String
    var warrantyEnd: Date
}

/// A local notification the scheduler can hand to `UNUserNotificationCenter`
/// without this type knowing about that API.
struct PlannedLocalNotification: Equatable {
    var identifier: String
    var title: String
    var body: String
    var fireDate: Date
    var leadDays: Int?
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

/// Pure date and copy planning for warranty reminders and the weekly note.
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

    static func expiryIdentifier(itemID: String, leadDays: Int) -> String {
        "\(expiryIdentifierPrefix)\(itemID).\(leadDays)"
    }

    static func expiryIdentifiers(forItemID itemID: String, leadDays: [Int] = [30, 7]) -> [String] {
        leadDays.map { expiryIdentifier(itemID: itemID, leadDays: $0) }
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

    /// Soonest expiry reminders first, capped at `expiryBudget`.
    func expiryNotifications(for items: [ExpiryReminderItem]) -> [PlannedLocalNotification] {
        var planned: [PlannedLocalNotification] = []
        planned.reserveCapacity(items.count * leadDays.count)
        for item in items {
            for lead in leadDays {
                guard let fire = triggerDate(expiry: item.warrantyEnd, leadDays: lead) else { continue }
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
                        leadDays: lead
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
            leadDays: nil
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

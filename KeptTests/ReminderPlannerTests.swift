import Foundation
import Testing
@testable import Kept

@Suite("Warranty and weekly reminders")
struct ReminderPlannerTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    @Test("30- and 7-day triggers land at 09:00 and skip past dates")
    func leadDatesSkipThePast() throws {
        let now = utcDate(2026, 6, 1, hour: 10)
        let expiry = utcDate(2026, 6, 20, hour: 15)
        let planner = ReminderPlanner(now: now, calendar: utc)
        let item = ExpiryReminderItem(id: "lamp", itemName: "Lamp", merchant: "IKEA", warrantyEnd: expiry)

        let thirty = planner.triggerDate(expiry: expiry, leadDays: 30)
        let seven = planner.triggerDate(expiry: expiry, leadDays: 7)
        #expect(thirty == nil)

        let fire = try #require(seven)
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        #expect(parts.year == 2026)
        #expect(parts.month == 6)
        #expect(parts.day == 13)
        #expect(parts.hour == 9)
        #expect(parts.minute == 0)

        let notes = planner.expiryNotifications(for: [item])
        #expect(notes.count == 1)
        #expect(notes[0].identifier == "kept.warranty.lamp.7")
        #expect(notes[0].leadDays == 7)
        #expect(notes[0].body.contains("Lamp"))
        #expect(notes[0].body.contains("IKEA"))
        #expect(notes[0].body.contains("7"))
    }

    @Test("both leads are scheduled when they are still in the future")
    func bothLeads() {
        let now = utcDate(2026, 1, 1, hour: 8)
        let expiry = utcDate(2026, 8, 1, hour: 15)
        let planner = ReminderPlanner(now: now, calendar: utc)
        let notes = planner.expiryNotifications(for: [
            ExpiryReminderItem(id: "phone", itemName: "Phone", merchant: "Apple", warrantyEnd: expiry)
        ])

        #expect(notes.map(\.leadDays) == [30, 7] as [Int?])
        let first = utc.dateComponents([.year, .month, .day, .hour, .minute], from: notes[0].fireDate)
        let second = utc.dateComponents([.year, .month, .day, .hour, .minute], from: notes[1].fireDate)
        #expect(first.month == 7)
        #expect(first.day == 2)
        #expect(first.hour == 9)
        #expect(second.month == 7)
        #expect(second.day == 25)
        #expect(second.hour == 9)
        #expect(notes[0].identifier == "kept.warranty.phone.30")
        #expect(notes[1].identifier == "kept.warranty.phone.7")
    }

    @Test("a trigger at exactly now, or after the warranty has ended, is skipped")
    func skipsNowAndExpired() {
        let now = utcDate(2026, 6, 13, hour: 9)
        let expiry = utcDate(2026, 6, 20, hour: 15)
        let planner = ReminderPlanner(now: now, calendar: utc)
        #expect(planner.triggerDate(expiry: expiry, leadDays: 7) == nil)
        #expect(planner.triggerDate(expiry: expiry, leadDays: 30) == nil)

        let ended = utcDate(2026, 5, 1, hour: 12)
        #expect(planner.expiryNotifications(for: [
            ExpiryReminderItem(id: "old", itemName: "Coat", merchant: "", warrantyEnd: ended)
        ]).isEmpty)
    }

    @Test("empty merchant and item names stay readable")
    func fallbackCopy() {
        let body = ReminderCopy.expiryBody(itemName: "  ", merchant: " ", leadDays: 30)
        #expect(body.contains("your purchase"))
        #expect(body.contains("30"))
        #expect(!body.contains("from"))
    }

    @Test("9:00 wall clock holds across a US daylight-saving change")
    func daylightSavingWallClock() throws {
        let now = nyDate(2026, 1, 1, hour: 8)
        let planner = ReminderPlanner(now: now, calendar: newYork)

        // 2026-03-08 is the spring-forward day. April 7 minus 30 days is that day.
        let springExpiry = nyDate(2026, 4, 7, hour: 15)
        let spring = try #require(planner.triggerDate(expiry: springExpiry, leadDays: 30))
        let springParts = newYork.dateComponents([.year, .month, .day, .hour, .minute], from: spring)
        #expect(springParts.year == 2026)
        #expect(springParts.month == 3)
        #expect(springParts.day == 8)
        #expect(springParts.hour == 9)
        #expect(springParts.minute == 0)

        // 2026-11-01 is the fall-back day. December 1 minus 30 days is that day.
        let fallExpiry = nyDate(2026, 12, 1, hour: 15)
        let fall = try #require(planner.triggerDate(expiry: fallExpiry, leadDays: 30))
        let fallParts = newYork.dateComponents([.year, .month, .day, .hour, .minute], from: fall)
        #expect(fallParts.month == 11)
        #expect(fallParts.day == 1)
        #expect(fallParts.hour == 9)
        #expect(fallParts.minute == 0)
    }

    @Test("the pending-notification budget keeps the soonest triggers")
    func budgetKeepsSoonest() {
        let now = utcDate(2026, 1, 1, hour: 8)
        var items: [ExpiryReminderItem] = []
        var expected: [(id: String, fire: Date)] = []
        for offset in 0..<40 {
            let expiry = utc.date(byAdding: .day, value: 60 + offset, to: now)!
            let id = "item-\(offset)"
            items.append(ExpiryReminderItem(id: id, itemName: "Item \(offset)", merchant: "Shop", warrantyEnd: expiry))
            for lead in [30, 7] {
                let day = utc.date(byAdding: .day, value: -lead, to: expiry)!
                var parts = utc.dateComponents([.year, .month, .day], from: day)
                parts.hour = 9
                parts.minute = 0
                parts.second = 0
                let fire = utc.date(from: parts)!
                expected.append((ReminderPlanner.expiryIdentifier(itemID: id, leadDays: lead), fire))
            }
        }
        expected.sort { lhs, rhs in
            if lhs.fire != rhs.fire { return lhs.fire < rhs.fire }
            return lhs.id < rhs.id
        }

        let budget = 5
        let planner = ReminderPlanner(now: now, calendar: utc, expiryBudget: budget)
        let notes = planner.expiryNotifications(for: items)
        #expect(notes.count == budget)
        #expect(notes.map(\.identifier) == expected.prefix(budget).map(\.id))
        #expect(notes.map(\.fireDate) == expected.prefix(budget).map(\.fire))
        #expect(zip(notes, notes.dropFirst()).allSatisfy { $0.0.fireDate <= $0.1.fireDate })

        let cappedAtSystem = ReminderPlanner(now: now, calendar: utc, expiryBudget: 64)
        let many = cappedAtSystem.expiryNotifications(for: items)
        #expect(many.count == 64)
        #expect(many.map(\.identifier) == expected.prefix(64).map(\.id))
        #expect(ReminderPlanner.defaultExpiryBudget == 63)
        #expect(ReminderPlanner.defaultExpiryBudget < ReminderPlanner.systemPendingLimit)
    }

    @Test("weekly reminder is 7 days later at 18:00 and stays in the future")
    func weeklyFireDate() {
        let lastOpen = utcDate(2026, 6, 1, hour: 22, minute: 15)
        let planner = ReminderPlanner(now: lastOpen, calendar: utc)
        let fire = planner.weeklyFireDate(lastOpen: lastOpen)
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        #expect(parts.year == 2026)
        #expect(parts.month == 6)
        #expect(parts.day == 8)
        #expect(parts.hour == 18)
        #expect(parts.minute == 0)
        #expect(fire > lastOpen)

        let dstOpen = nyDate(2026, 3, 6, hour: 12)
        let dstPlanner = ReminderPlanner(now: dstOpen, calendar: newYork)
        let dstFire = dstPlanner.weeklyFireDate(lastOpen: dstOpen)
        let dstParts = newYork.dateComponents([.year, .month, .day, .hour, .minute], from: dstFire)
        #expect(dstParts.month == 3)
        #expect(dstParts.day == 13)
        #expect(dstParts.hour == 18)

        let staleOpen = utcDate(2026, 1, 1, hour: 10)
        let later = utcDate(2026, 1, 20, hour: 12)
        let stalePlanner = ReminderPlanner(now: later, calendar: utc)
        let recovered = stalePlanner.weeklyFireDate(lastOpen: staleOpen)
        #expect(recovered > later)
    }

    @Test("weekly lines rotate and rescheduling reuses one identifier")
    func weeklyRotationAndIdentity() async {
        #expect(WeeklyReminderCopy.lines.count >= 4)
        #expect(WeeklyReminderCopy.lines.count <= 6)
        #expect(Set(WeeklyReminderCopy.lines).count == WeeklyReminderCopy.lines.count)
        #expect(WeeklyReminderCopy.line(at: 0) == WeeklyReminderCopy.lines[0])
        #expect(WeeklyReminderCopy.line(at: WeeklyReminderCopy.lines.count) == WeeklyReminderCopy.lines[0])
        #expect(WeeklyReminderCopy.line(at: -1) == WeeklyReminderCopy.lines[WeeklyReminderCopy.lines.count - 1])
        for line in WeeklyReminderCopy.lines {
            #expect(!line.contains("!"))
            #expect(!line.localizedCaseInsensitiveContains("forgot"))
            #expect(line.unicodeScalars.allSatisfy { $0.value < 0x1F000 })
        }
        #expect(WeeklyReminderCopy.localizedLine(at: 2) == WeeklyReminderCopy.line(at: 2))

        let firstDay = utcDate(2026, 6, 1, hour: 11)
        let nextDay = utc.date(byAdding: .day, value: 1, to: firstDay)!
        let firstIndex = WeeklyReminderCopy.index(for: firstDay, calendar: utc)
        let secondIndex = WeeklyReminderCopy.index(for: nextDay, calendar: utc)
        #expect(secondIndex == (firstIndex + 1) % WeeklyReminderCopy.lines.count)
        #expect(WeeklyReminderCopy.index(for: firstDay, calendar: utc) == firstIndex)

        let planner = ReminderPlanner(now: firstDay, calendar: utc)
        let first = planner.weeklyNotification(lastOpen: firstDay)
        let second = planner.weeklyNotification(lastOpen: nextDay)
        #expect(first.identifier == ReminderPlanner.weeklyIdentifier)
        #expect(second.identifier == ReminderPlanner.weeklyIdentifier)
        #expect(first.body == WeeklyReminderCopy.line(at: firstIndex))
        #expect(second.body == WeeklyReminderCopy.line(at: secondIndex))
        #expect(first.body != second.body)

        let center = FakeReminderNotificationCenter()
        center.pending[ReminderPlanner.weeklyIdentifier] = first
        let scheduler = ReminderNotificationScheduler(center: center, planner: planner)
        await scheduler.rescheduleWeekly(lastOpen: firstDay, enabled: true)
        await scheduler.rescheduleWeekly(lastOpen: nextDay, enabled: true)

        let weekly = center.pending.filter { $0.key == ReminderPlanner.weeklyIdentifier }
        #expect(weekly.count == 1)
        #expect(weekly[ReminderPlanner.weeklyIdentifier]?.fireDate == second.fireDate)
        #expect(weekly[ReminderPlanner.weeklyIdentifier]?.body == second.body)
        #expect(center.events.contains(.remove([ReminderPlanner.weeklyIdentifier])))
        let scheduleEvents = center.events.compactMap { event -> [String]? in
            if case .schedule(let identifiers) = event { return identifiers }
            return nil
        }
        #expect(scheduleEvents.allSatisfy { $0 == [ReminderPlanner.weeklyIdentifier] })

        await scheduler.rescheduleWeekly(lastOpen: nextDay, enabled: false)
        #expect(center.pending[ReminderPlanner.weeklyIdentifier] == nil)
    }

    @Test("expiry reconcile drops stale ids and leaves room around other notifications")
    func reconcileBudgetsAroundOtherNotifications() async {
        let now = utcDate(2026, 1, 1, hour: 8)
        var items: [ExpiryReminderItem] = []
        for offset in 0..<10 {
            let expiry = utc.date(byAdding: .day, value: 80 + offset, to: now)!
            items.append(
                ExpiryReminderItem(
                    id: "row-\(offset)",
                    itemName: "Row \(offset)",
                    merchant: "Shop",
                    warrantyEnd: expiry
                )
            )
        }
        let planner = ReminderPlanner(now: now, calendar: utc)
        let center = FakeReminderNotificationCenter()
        for index in 0..<60 {
            let identifier = "kept.offer.\(index)"
            center.pending[identifier] = PlannedLocalNotification(
                identifier: identifier,
                title: "Offer",
                body: "Offer",
                fireDate: now,
                leadDays: nil
            )
        }
        center.pending[ReminderPlanner.weeklyIdentifier] = planner.weeklyNotification(lastOpen: now)
        center.pending["kept.coverage.stale.warranty.14"] = PlannedLocalNotification(
            identifier: "kept.coverage.stale.warranty.14",
            title: "Old",
            body: "Old",
            fireDate: now,
            leadDays: 14
        )

        let scheduler = ReminderNotificationScheduler(center: center, planner: planner)
        await scheduler.reconcileExpiry(items: items, enabled: true)

        let expiry = center.pending.filter { ReminderPlanner.isManagedExpiryIdentifier($0.key) }
        #expect(expiry.count == 3)
        #expect(center.pending["kept.coverage.stale.warranty.14"] == nil)
        #expect(center.pending[ReminderPlanner.weeklyIdentifier] != nil)
        #expect(center.pending.keys.filter { $0.hasPrefix("kept.offer.") }.count == 60)

        let soonest = planner.expiryNotifications(for: items)
        #expect(expiry.values.map(\.identifier).sorted() == soonest.prefix(3).map(\.identifier).sorted())

        await scheduler.reconcileExpiry(items: items, enabled: false)
        #expect(center.pending.keys.contains { ReminderPlanner.isManagedExpiryIdentifier($0) } == false)
        #expect(center.pending[ReminderPlanner.weeklyIdentifier] != nil)
    }

    @Test("the system prompt waits until the paywall is gone and is not repeated")
    func permissionTiming() {
        #expect(
            NotificationPromptTiming.decision(hasAsked: false, paywallWillPresent: true)
                == .waitUntilPaywallDismisses
        )
        #expect(
            NotificationPromptTiming.decision(hasAsked: false, paywallWillPresent: false) == .askNow
        )
        #expect(NotificationPromptTiming.decision(hasAsked: true, paywallWillPresent: false) == .skip)
        #expect(NotificationPromptTiming.decision(hasAsked: true, paywallWillPresent: true) == .skip)
    }

    @Test("item tokens stay deterministic for the same row")
    func stableToken() {
        let token = ReminderPlanner.itemToken(forPersistentID: "persistent-id-1")
        #expect(token == ReminderPlanner.itemToken(forPersistentID: "persistent-id-1"))
        #expect(token != ReminderPlanner.itemToken(forPersistentID: "persistent-id-2"))
        #expect(
            ReminderPlanner.legacyCoverageIdentifiers(forItemID: token)
                .contains("kept.coverage.\(token).warranty.14")
        )
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
        date(year, month, day, hour: hour, minute: minute, calendar: utc)
    }

    private func nyDate(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
        date(year, month, day, hour: hour, minute: minute, calendar: newYork)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }
}

private final class FakeReminderNotificationCenter: ReminderNotificationCenter {
    enum Event: Equatable {
        case remove([String])
        case schedule([String])
    }

    var pending: [String: PlannedLocalNotification] = [:]
    var events: [Event] = []

    func pendingIdentifiers() async -> [String] {
        Array(pending.keys)
    }

    func removePending(withIdentifiers identifiers: [String]) async {
        events.append(.remove(identifiers))
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
        }
    }

    func schedule(_ notifications: [PlannedLocalNotification], calendar _: Calendar) async {
        events.append(.schedule(notifications.map(\.identifier)))
        for notification in notifications {
            pending[notification.identifier] = notification
        }
    }
}

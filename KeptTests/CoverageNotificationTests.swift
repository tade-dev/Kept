import Foundation
import Testing
@testable import Kept

@Suite("Coverage notifications")
struct CoverageNotificationTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    @Test("fire date is 14 days before expiry at 09:30")
    func fireDateLeadWindow() {
        let expiry = date(2026, 12, 20, hour: 15)
        let now = date(2026, 8, 1, hour: 12)
        let fire = CoverageNotificationScheduler.fireDate(
            expiry: expiry,
            now: now,
            calendar: calendar
        )

        #expect(fire != nil)
        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fire!
        )
        #expect(comps.year == 2026)
        #expect(comps.month == 12)
        #expect(comps.day == 6)
        #expect(comps.hour == 9)
        #expect(comps.minute == 30)
    }

    @Test("inside lead window still schedules before expiry")
    func fireDateInsideWindow() {
        let now = date(2026, 8, 10, hour: 12)
        let expiry = date(2026, 8, 20, hour: 12)
        let fire = CoverageNotificationScheduler.fireDate(
            expiry: expiry,
            now: now,
            calendar: calendar
        )

        #expect(fire != nil)
        #expect(fire! > now)
        #expect(fire! < expiry)
    }

    @Test("expired terms are not scheduled")
    func fireDateExpired() {
        let now = date(2026, 8, 10, hour: 12)
        let expiry = date(2026, 8, 1, hour: 12)
        let fire = CoverageNotificationScheduler.fireDate(
            expiry: expiry,
            now: now,
            calendar: calendar
        )
        #expect(fire == nil)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }
}

import SwiftUI

/// Maps a coverage end date onto `CoverageCard` without storing anything.
enum CoverageCardMapping {
    /// Matches the coverage ring's 14-day baseline in `CoverageCard`.
    static let endingSoonWithinDays = 14

    static func daysRemaining(
        until end: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let start = calendar.startOfDay(for: now)
        let finish = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: start, to: finish).day ?? 0
    }

    static func phase(daysRemaining: Int) -> CoverageCard.Phase {
        if daysRemaining < 0 { return .expired }
        if daysRemaining <= endingSoonWithinDays { return .endingSoon }
        return .covered
    }

    /// Year and month groups for the adaptive countdown. Nil under 365 days,
    /// which keeps the "N days left" rendering.
    struct YearMonth: Equatable {
        var years: Int
        var months: Int
    }

    static func yearMonth(
        daysRemaining: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> YearMonth? {
        guard daysRemaining >= 365 else { return nil }
        guard let end = calendar.date(byAdding: .day, value: daysRemaining, to: now) else { return nil }
        let parts = calendar.dateComponents([.year, .month], from: now, to: end)
        let years = max(0, parts.year ?? 0)
        let months = max(0, parts.month ?? 0)
        guard years > 0 || months > 0 else { return nil }
        return YearMonth(years: years, months: months)
    }

    /// Spoken remainder. Adaptive counts use `DateComponentsFormatter` so
    /// VoiceOver hears "1 year 8 months left" rather than "yr" and "mo".
    static func spokenRemaining(daysRemaining: Int, yearMonth: YearMonth?) -> String {
        if let yearMonth, let spoken = spokenYearMonth(yearMonth) {
            return String(localized: "\(spoken) left", comment: "VoiceOver coverage duration, e.g. 1 year 8 months left")
        }
        if daysRemaining == 1 {
            return String(localized: "1 day left", comment: "VoiceOver coverage duration")
        }
        return String(localized: "\(daysRemaining) days left", comment: "VoiceOver coverage duration")
    }

    private static func spokenYearMonth(_ yearMonth: YearMonth) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        var units: NSCalendar.Unit = []
        var components = DateComponents()
        if yearMonth.years > 0 {
            units.insert(.year)
            components.year = yearMonth.years
        }
        if yearMonth.months > 0 {
            units.insert(.month)
            components.month = yearMonth.months
        }
        formatter.allowedUnits = units
        return formatter.string(from: components)
    }
}

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
}

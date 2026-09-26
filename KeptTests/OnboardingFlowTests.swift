import Foundation
import Testing
@testable import Kept

@Suite("Onboarding flow")
@MainActor
struct OnboardingFlowTests {
    @Test("value beat is the step immediately after welcome")
    func stepOrder() {
        #expect(OnboardingStep.allCases == [
            .welcome,
            .valueBeat,
            .leadTimes,
            .privacy,
            .existingReceipts,
            .notifications
        ])
        #expect(OnboardingStep.welcome.next == .valueBeat)
        #expect(OnboardingStep.valueBeat.previous == .welcome)
        #expect(OnboardingStep.notifications.next == nil)
    }

    @Test("chrome starts on the value beat and fills across the remaining steps")
    func chromeProgress() {
        #expect(OnboardingStep.welcome.showsChrome == false)
        #expect(OnboardingStep.welcome.progressFraction == nil)
        #expect(OnboardingStep.valueBeat.showsChrome)
        #expect(OnboardingStep.valueBeat.progressFraction == 1.0 / 5.0)
        #expect(OnboardingStep.notifications.showsChrome)
        #expect(OnboardingStep.notifications.progressFraction == 1.0)
    }

    @Test("every step can advance except an empty lead-time selection")
    func canAdvance() {
        let coordinator = OnboardingCoordinator()
        for step in OnboardingStep.allCases {
            coordinator.step = step
            #expect(coordinator.canAdvance)
        }
        coordinator.step = .leadTimes
        coordinator.result.warningLeadTimes = []
        #expect(coordinator.canAdvance == false)
    }

    @Test("finish marks onboarded and does not write tracked categories")
    func finishLeavesTrackedCategoriesUntouched() {
        let defaults = UserDefaults.standard
        let keys = [
            SettingsKeys.hasOnboarded,
            SettingsKeys.hasExistingReceipts,
            SettingsKeys.leadDaysCSV,
            SettingsKeys.trackedCategoriesCSV
        ]
        let snapshot = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, snapshot) {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set("electronics,clothing", forKey: SettingsKeys.trackedCategoriesCSV)
        let coordinator = OnboardingCoordinator()
        coordinator.result.warningLeadTimes = [14, 30]
        coordinator.result.hasExistingReceipts = true
        coordinator.finish()

        #expect(SettingsSnapshot.hasOnboarded)
        #expect(SettingsSnapshot.hasExistingReceipts)
        #expect(defaults.string(forKey: SettingsKeys.trackedCategoriesCSV) == "electronics,clothing")
        #expect(defaults.string(forKey: SettingsKeys.leadDaysCSV) == "14,30")
    }

    @Test("value beat rests on covered with days remaining, never expired")
    func valueBeatResolvesCovered() {
        #expect(ValueBeatScript.restingPhase == .covered)
        #expect(ValueBeatScript.restingDays > CoverageCardMapping.endingSoonWithinDays)
        #expect(ValueBeatScript.ticks.last == ValueBeatScript.restingDays)
        #expect(ValueBeatScript.ticks.allSatisfy {
            CoverageCardMapping.phase(daysRemaining: $0) == .covered
        })
        #expect(SampleCoverageCard.phase == .covered)
        #expect(SampleCoverageCard.daysRemaining == ValueBeatScript.restingDays)
    }
}

@Suite("First-save payoff")
struct FirstSavePayoffTests {
    @Test("sheet shows once, and only for the 0 to 1 transition")
    func showsOnceOnZeroToOne() {
        #expect(FirstSavePayoffPolicy.shouldPresent(previousCount: 0, newCount: 1, hasSeen: false))
        #expect(FirstSavePayoffPolicy.shouldPresent(previousCount: 0, newCount: 1, hasSeen: true) == false)
        #expect(FirstSavePayoffPolicy.shouldPresent(previousCount: 1, newCount: 2, hasSeen: false) == false)
        #expect(FirstSavePayoffPolicy.shouldPresent(previousCount: 5, newCount: 6, hasSeen: false) == false)
        #expect(FirstSavePayoffPolicy.shouldPresent(previousCount: 0, newCount: 0, hasSeen: false) == false)
        #expect(FirstSavePayoffPolicy.shouldPresent(previousCount: 2, newCount: 1, hasSeen: false) == false)
    }
}

@Suite("Coverage card mapping")
struct CoverageCardMappingTests {
    @Test("phase follows the 14-day covered window and treats today as ending soon")
    func phaseBoundaries() {
        #expect(CoverageCardMapping.phase(daysRemaining: -1) == .expired)
        #expect(CoverageCardMapping.phase(daysRemaining: 0) == .endingSoon)
        #expect(CoverageCardMapping.phase(daysRemaining: 14) == .endingSoon)
        #expect(CoverageCardMapping.phase(daysRemaining: 15) == .covered)
    }

    @Test("day count is whole calendar days, not a raw 24-hour slice")
    func calendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 23))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 1))!
        #expect(CoverageCardMapping.daysRemaining(until: end, now: now, calendar: calendar) == 1)
    }
}

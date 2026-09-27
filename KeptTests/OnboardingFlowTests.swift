import Foundation
import Testing
@testable import Kept

@Suite("Onboarding flow")
@MainActor
struct OnboardingFlowTests {
    @Test("key moment is the step immediately after welcome")
    func stepOrder() {
        #expect(OnboardingStep.allCases == [
            .welcome,
            .keyMoment,
            .leadTimes,
            .privacy,
            .existingReceipts,
            .notifications
        ])
        #expect(OnboardingStep.welcome.next == .keyMoment)
        #expect(OnboardingStep.keyMoment.previous == .welcome)
        #expect(OnboardingStep.notifications.next == nil)
    }

    @Test("chrome starts on the key moment and fills across the remaining steps")
    func chromeProgress() {
        #expect(OnboardingStep.welcome.showsChrome == false)
        #expect(OnboardingStep.welcome.progressFraction == nil)
        #expect(OnboardingStep.keyMoment.showsChrome)
        #expect(OnboardingStep.keyMoment.progressFraction == 1.0 / 5.0)
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

    @Test("key moment resolves to covered with 214 days, never expired")
    func keyMomentResolvesCovered() {
        #expect(KeyMomentScript.phase == .covered)
        #expect(KeyMomentScript.daysRemaining == 214)
        #expect(KeyMomentScript.daysRemaining > CoverageCardMapping.endingSoonWithinDays)
        #expect(KeyMomentScript.questionMilliseconds == 1200)
        #expect(KeyMomentScript.payoffMilliseconds == 550)
        #expect(SampleCoverageCard.phase == .covered)
        #expect(SampleCoverageCard.daysRemaining == 608)
        #expect(SampleCoverageCard.merchant == "Dyson")
    }
}

@Suite("First-save payoff")
struct FirstSavePayoffTests {
    @Test("sheet requires an active warranty and does not consume the flag otherwise")
    func eligibleOnlyWithFutureWarranty() {
        let future = Date(timeIntervalSinceNow: 86_400)
        let past = Date(timeIntervalSinceNow: -86_400)
        #expect(FirstSavePayoff.isEligible(warrantyExpiry: future, hasShown: false))
        #expect(FirstSavePayoff.isEligible(warrantyExpiry: nil, hasShown: false) == false)
        #expect(FirstSavePayoff.isEligible(warrantyExpiry: past, hasShown: false) == false)
        #expect(FirstSavePayoff.isEligible(warrantyExpiry: future, hasShown: true) == false)
    }

    @Test("a later covered save can still show the sheet when the first save was not eligible")
    func waitsForFirstCoveredSave() {
        #expect(FirstSavePayoff.isEligible(warrantyExpiry: Date(timeIntervalSinceNow: 86_400), hasShown: false))
    }

    @Test("paywall is requested on the first save when the sheet is skipped")
    func paywallWhenSheetSkipped() {
        #expect(FirstSavePayoff.shouldRequestPaywallWithoutSheet(
            previousCount: 0, newCount: 1, willShowSheet: false
        ))
        #expect(FirstSavePayoff.shouldRequestPaywallWithoutSheet(
            previousCount: 0, newCount: 1, willShowSheet: true
        ) == false)
        #expect(FirstSavePayoff.shouldRequestPaywallWithoutSheet(
            previousCount: 1, newCount: 2, willShowSheet: false
        ) == false)
    }

    @Test("an existing library stamps the flag so the sheet never appears")
    func existingLibraryStamps() {
        #expect(FirstSavePayoff.shouldStampExistingLibrary(hasShown: false, purchaseCount: 3))
        #expect(FirstSavePayoff.shouldStampExistingLibrary(hasShown: false, purchaseCount: 0) == false)
        #expect(FirstSavePayoff.shouldStampExistingLibrary(hasShown: true, purchaseCount: 3) == false)
    }

    @Test("phase uses the largest lead time, and the day count is whole days")
    func phaseAndDays() {
        #expect(FirstSavePayoff.phase(daysRemaining: 10, leadDays: [14, 30]) == .endingSoon)
        #expect(FirstSavePayoff.phase(daysRemaining: 31, leadDays: [14, 30]) == .covered)
        #expect(FirstSavePayoff.phase(daysRemaining: -1, leadDays: [14]) == .expired)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 23))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 1))!
        #expect(FirstSavePayoff.daysLeft(until: end, now: now, calendar: calendar) == 1)
    }
}

@Suite("Front-door paywall ordering")
struct OnboardingPaywallPolicyTests {
    @Test("onboarding finish does not request the paywall")
    func notAfterOnboarding() {
        #expect(OnboardingPaywallPolicy.trigger(for: .onboardingFinished, hasSeenPaywall: false) == nil)
        #expect(OnboardingPaywallPolicy.trigger(for: .onboardingFinished, hasSeenPaywall: true) == nil)
    }

    @Test("first-save sheet dismiss requests the paywall once")
    func afterFirstSaveSheet() {
        #expect(
            OnboardingPaywallPolicy.trigger(for: .firstSaveSheetDismissed, hasSeenPaywall: false) == .showPaywall
        )
        #expect(OnboardingPaywallPolicy.trigger(for: .firstSaveSheetDismissed, hasSeenPaywall: true) == nil)
    }

    @Test("skipping the sheet on a save with no warranty still requests the paywall once")
    func afterFirstSaveWithoutSheet() {
        #expect(
            OnboardingPaywallPolicy.trigger(for: .firstSaveWithoutPayoffSheet, hasSeenPaywall: false) == .showPaywall
        )
        #expect(OnboardingPaywallPolicy.trigger(for: .firstSaveWithoutPayoffSheet, hasSeenPaywall: true) == nil)
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

    @Test("adaptive remainder is years and months at 365 days or more")
    func adaptiveYearMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        #expect(CoverageCardMapping.yearMonth(daysRemaining: 214, now: now, calendar: calendar) == nil)
        #expect(CoverageCardMapping.yearMonth(daysRemaining: 608, now: now, calendar: calendar) == .init(years: 1, months: 8))
        #expect(CoverageCardMapping.yearMonth(daysRemaining: 730, now: now, calendar: calendar) == .init(years: 2, months: 0))
    }

    @Test("voiceover label names the sample, the cover, and the proof")
    func accessibilityLabel() {
        let sample = CoverageCard.accessibilityLabel(
            isResolved: true,
            isSample: true,
            spokenLeadIn: nil,
            merchant: "Dyson",
            item: "V15 Detect",
            phaseLabel: "Covered",
            remainingSpoken: "1 year 8 months left",
            showsReceipt: true,
            showsClaimPackReady: false
        )
        #expect(sample == "Sample. Dyson, V15 Detect. Covered, 1 year 8 months left. Receipt saved.")

        let checking = CoverageCard.accessibilityLabel(
            isResolved: false,
            isSample: false,
            spokenLeadIn: "Example",
            merchant: "Sony",
            item: "WH-1000XM5 Headphones",
            phaseLabel: "Covered",
            remainingSpoken: "214 days left",
            showsReceipt: true,
            showsClaimPackReady: true
        )
        #expect(checking == "Checking cover for WH-1000XM5 Headphones")
    }
}

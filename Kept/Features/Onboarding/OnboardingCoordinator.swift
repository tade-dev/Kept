import Foundation
import Observation
import SwiftUI

/// Ordered first-run steps. Welcome is full-bleed; the progress bar and back
/// chevron show on every step after it. Categories and the "Setting up"
/// interstitial are gone — the value beat is the first step after Welcome.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case valueBeat = 1
    case leadTimes = 2
    case privacy = 3
    case existingReceipts = 4
    case notifications = 5

    var id: Int { rawValue }

    var showsChrome: Bool {
        self != .welcome
    }

    /// Fraction 0–1 across the chrome steps (a contiguous 1...n range), or nil
    /// when the bar is hidden.
    var progressFraction: Double? {
        guard showsChrome else { return nil }
        let chromeCount = Double(Self.allCases.filter(\.showsChrome).count)
        guard chromeCount > 0 else { return nil }
        return Double(rawValue) / chromeCount
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        guard rawValue > 0 else { return nil }
        return OnboardingStep(rawValue: rawValue - 1)
    }
}

struct OnboardingResult: Equatable {
    var warningLeadTimes: Set<Int>
    var hasExistingReceipts: Bool

    static let empty = OnboardingResult(
        warningLeadTimes: [14],
        hasExistingReceipts: false
    )
}

/// Owns the current step and collected answers. Presented full-screen; dismissed
/// by writing `hasOnboarded`. Persists answers to Settings on `finish()`.
@MainActor
@Observable
final class OnboardingCoordinator {
    var step: OnboardingStep = .welcome
    var result: OnboardingResult = .empty

    /// Whether the flow has enough state to enable the "Continue" button on the current step.
    var canAdvance: Bool {
        switch step {
        case .welcome, .valueBeat, .privacy, .existingReceipts, .notifications:
            return true
        case .leadTimes:
            return !result.warningLeadTimes.isEmpty
        }
    }

    // MARK: - Navigation

    func advance() {
        guard let next = step.next else { return }
        step = next
    }

    func back() {
        guard let previous = step.previous else { return }
        step = previous
    }

    // MARK: - Lead-time answers

    func toggleLead(_ days: Int) {
        if result.warningLeadTimes.contains(days) {
            // Never let the user clear all — keep at least one.
            guard result.warningLeadTimes.count > 1 else { return }
            result.warningLeadTimes.remove(days)
        } else {
            result.warningLeadTimes.insert(days)
        }
    }

    // MARK: - Persistence

    /// Writes lead times and flips `hasOnboarded`. Called from the last step
    /// (notifications). Does not write `trackedCategoriesCSV` — that key is
    /// legacy and has no readers.
    func finish() {
        SettingsSnapshot.write(leadDays: result.warningLeadTimes)
        SettingsSnapshot.markOnboarded(hasExistingReceipts: result.hasExistingReceipts)
    }
}

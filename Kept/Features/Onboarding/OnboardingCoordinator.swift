import Foundation
import Observation
import SwiftUI

/// Ordered first-run steps. Welcome is full-bleed; the progress bar and back
/// chevron show on every step after it. Categories, the lead-time picker,
/// and the "Setting up" interstitial stay removed. The key moment is the
/// first step after Welcome.
enum OnboardingStep: Int, CaseIterable, Identifiable, Equatable {
    case welcome = 0
    case keyMoment = 1
    case privacy = 2
    case existingReceipts = 3
    case notifications = 4

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
    var hasExistingReceipts: Bool

    static let empty = OnboardingResult(hasExistingReceipts: false)
}

/// Owns the current step and collected answers. Presented full-screen; dismissed
/// by writing `hasOnboarded`. Persists answers to Settings on `finish()`.
@MainActor
@Observable
final class OnboardingCoordinator {
    var step: OnboardingStep = .welcome
    var result: OnboardingResult = .empty
    /// After the key moment has resolved once, returning to the step shows
    /// the final frame with no replay.
    var hasPlayedKeyMoment = false

    /// Whether the flow has enough state to enable the "Continue" button on the current step.
    var canAdvance: Bool {
        switch step {
        case .welcome, .keyMoment, .privacy, .existingReceipts, .notifications:
            return true
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

    // MARK: - Persistence

    /// Flips `hasOnboarded`. Called from the last step (notifications).
    /// Does not write `trackedCategoriesCSV` or the retired lead-time keys.
    func finish() {
        SettingsSnapshot.markOnboarded(hasExistingReceipts: result.hasExistingReceipts)
    }
}

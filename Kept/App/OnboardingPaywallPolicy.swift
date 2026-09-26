import Foundation

/// When the one-time front-door paywall may appear.
///
/// Revenue decision, kept separate so it can be reverted on its own:
/// the paywall waits until the first save. If that save shows the payoff
/// sheet, the paywall waits for the sheet to dismiss. If the sheet is
/// skipped (no active warranty), the paywall still appears.
/// Finishing onboarding does not present it.
enum OnboardingPaywallPolicy {
    enum Event: Equatable {
        case onboardingFinished
        case firstSaveSheetDismissed
        case firstSaveWithoutPayoffSheet
    }

    enum Action: Equatable {
        case showPaywall
    }

    static func trigger(for event: Event, hasSeenPaywall: Bool) -> Action? {
        guard !hasSeenPaywall else { return nil }
        switch event {
        case .onboardingFinished:
            return nil
        case .firstSaveSheetDismissed, .firstSaveWithoutPayoffSheet:
            return .showPaywall
        }
    }
}

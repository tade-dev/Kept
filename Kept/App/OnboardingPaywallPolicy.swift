import Foundation

/// When the one-time front-door paywall may appear.
///
/// Revenue decision, kept separate so it can be reverted on its own:
/// the paywall waits until the first-save payoff sheet is dismissed.
/// Finishing onboarding does not present it.
enum OnboardingPaywallPolicy {
    enum Event: Equatable {
        case onboardingFinished
        case firstSaveSheetDismissed
    }

    enum Action: Equatable {
        case showPaywall
    }

    static func trigger(for event: Event, hasSeenPaywall: Bool) -> Action? {
        guard !hasSeenPaywall else { return nil }
        switch event {
        case .onboardingFinished:
            return nil
        case .firstSaveSheetDismissed:
            return .showPaywall
        }
    }
}

import SwiftUI

/// Presents the library. When the user hasn't onboarded, overlays onboarding full-screen.
/// If the existing-receipts step was "Yes, a few", LibraryView opens capture
/// once the front-door paywall is not showing.
/// The front-door paywall itself waits until the first-save payoff sheet is dismissed.
///
/// On every cold launch a `SplashView` covers the whole scene for ~3s before
/// fading away — the seal + wordmark springs up from below and settles at
/// centre. Timing owned here so the splash → onboarding-cover sequencing
/// stays coordinated in one place.
struct RootView: View {
    @AppStorage(SettingsKeys.hasOnboarded) private var hasOnboarded: Bool = false
    @AppStorage(SettingsKeys.hasSeenOnboardingPaywall) private var hasSeenOnboardingPaywall: Bool = false
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw: String = AppearancePreference.system.rawValue
    @AppStorage(SettingsKeys.darkAccent) private var darkAccentRaw: String = DarkAccentPreference.midnight.rawValue
    @AppStorage("kept.textSize") private var textSizeRaw: String = KeptTextSize.system.rawValue
    @State private var openCaptureAfterOnboarding = false
    @State private var isSplashShowing = true
    /// Bound to the trial-entry paywall cover. Presented after the first-save
    /// payoff sheet dismisses, not at the end of onboarding. Persisted-once
    /// via `hasSeenOnboardingPaywall` so subsequent launches skip it.
    @State private var showsOnboardingPaywall = false

    /// Total splash budget from process launch to dismissal.
    private static let splashDuration: TimeInterval = 3.0

    private var userTextSize: KeptTextSize {
        KeptTextSize(rawValue: textSizeRaw) ?? .system
    }

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    private var darkAccent: DarkAccentPreference {
        DarkAccentPreference(rawValue: darkAccentRaw) ?? .midnight
    }

    var body: some View {
        // While splash is showing, LibraryView isn't in the tree at all
        // — so its `.fullScreenCover(isPresented: !hasOnboarded)` cannot
        // fire and clobber the splash on first launch. Once splash
        // retires, we swap to LibraryView which mounts its cover
        // attachment, and (if hasOnboarded is still false) onboarding
        // presents cleanly on top.
        Group {
            if isSplashShowing {
                SplashView()
                    .transition(.opacity)
            } else {
                LibraryView(
                    captureAfterOnboarding: $openCaptureAfterOnboarding,
                    paywallIsShowing: showsOnboardingPaywall,
                    onFirstSavePayoffDismissed: presentPaywallAfterFirstSave
                )
                    .fullScreenCover(isPresented: .constant(!hasOnboarded)) {
                        OnboardingView { hasExistingReceipts in
                            openCaptureAfterOnboarding = hasExistingReceipts
                            hasOnboarded = true
                        }
                        // Belt-and-braces: keep the status bar visible even if
                        // any nested view accidentally sets .persistentSystemOverlays(.hidden).
                        .persistentSystemOverlays(.visible)
                    }
                    .fullScreenCover(isPresented: $showsOnboardingPaywall) {
                        OnboardingPaywallGate()
                            .persistentSystemOverlays(.visible)
                    }
                    .onChange(of: showsOnboardingPaywall) { _, isPresented in
                        // Stamp the flag when the gate dismisses so subsequent
                        // launches never re-show it (regardless of whether
                        // the user bought, started a trial, or continued
                        // with free — every exit counts as "seen").
                        if !isPresented { hasSeenOnboardingPaywall = true }
                    }
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.splashDuration))
            withAnimation(.easeInOut(duration: 0.45)) {
                isSplashShowing = false
            }
        }
        // Apply user's in-app text-size override at the root so every
        // text token adopts it. When set to `.system` this is a no-op
        // and Kept keeps following iOS's Dynamic Type setting.
        .keptTextSize(userTextSize)
        .preferredColorScheme(appearance.colorScheme)
        .tint(darkAccent.tint)
    }

    /// Front-door paywall, after the first-save sheet — not after onboarding.
    private func presentPaywallAfterFirstSave() {
        guard OnboardingPaywallPolicy.trigger(
            for: .firstSaveSheetDismissed,
            hasSeenPaywall: hasSeenOnboardingPaywall
        ) == .showPaywall else { return }
        // Next runloop tick so the payoff sheet finishes dismissing before
        // the paywall cover presents.
        DispatchQueue.main.async {
            showsOnboardingPaywall = true
        }
    }
}

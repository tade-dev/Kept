import SwiftUI

/// Presents the library. When the user hasn't onboarded, overlays onboarding full-screen.
/// If step 4 was "Yes, a few", opens capture immediately after the cover dismisses.
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
    /// Bound to the trial-entry paywall cover. Flips true the moment the
    /// onboarding cover dismisses so the paywall lands immediately after —
    /// no gap frame of Library between the two covers. Persisted-once via
    /// `hasSeenOnboardingPaywall` so subsequent launches skip it.
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
                LibraryView()
                    .fullScreenCover(isPresented: .constant(!hasOnboarded)) {
                        OnboardingView { hasExistingReceipts in
                            openCaptureAfterOnboarding = hasExistingReceipts
                            hasOnboarded = true
                            // Chain the trial-entry paywall on next runloop
                            // tick so SwiftUI has time to dismiss the
                            // onboarding cover before the paywall cover
                            // presents (two full-screen covers can't animate
                            // simultaneously otherwise).
                            if !hasSeenOnboardingPaywall {
                                DispatchQueue.main.async {
                                    showsOnboardingPaywall = true
                                }
                            }
                        }
                        // Belt-and-braces: keep the status bar visible even if
                        // any nested view accidentally sets .persistentSystemOverlays(.hidden).
                        .persistentSystemOverlays(.visible)
                    }
                    .fullScreenCover(isPresented: $showsOnboardingPaywall) {
                        OnboardingPaywallGate()
                            .persistentSystemOverlays(.visible)
                    }
                    // Post-capture routing waits for the paywall gate to
                    // clear — no point auto-opening the scanner while the
                    // trial-entry sheet still owns the screen.
                    .sheet(isPresented: Binding(
                        get: { openCaptureAfterOnboarding && !showsOnboardingPaywall },
                        set: { openCaptureAfterOnboarding = $0 }
                    )) {
                        CaptureView()
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
}

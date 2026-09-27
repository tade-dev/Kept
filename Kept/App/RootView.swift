import SwiftUI

/// Presents the library. When the user hasn't onboarded, overlays onboarding full-screen.
/// If the existing-receipts step was "Yes, a few", LibraryView opens capture
/// once the front-door paywall is not showing.
/// The front-door paywall waits until the first save. If that save has an
/// active warranty, the payoff sheet comes first. If it does not, the
/// paywall still appears so it is not lost.
/// Notification permission is requested only after that paywall (or
/// immediately, if the paywall is not shown), never on top of either surface.
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
    /// Bound to the trial-entry paywall cover. Presented after the first save,
    /// once any payoff sheet has dismissed. Persisted-once via
    /// `hasSeenOnboardingPaywall` so subsequent launches skip it.
    @State private var showsOnboardingPaywall = false
    /// Owns pending deep-link destinations (App Store In-App Event Open,
    /// universal-link tap, custom-scheme tap). Held at Root scope so the
    /// URL can arrive during cold launch — before Library has mounted —
    /// without losing it while splash/onboarding play out.
    @State private var deepLinks = DeepLinkRouter()

    /// Whether the deep-link scanner sheet should be showing right now.
    /// Ties two concerns together: gate readiness (onboarding + trial
    /// paywall done) AND a pending `.scan` intent. Setter clears the
    /// pending intent when SwiftUI dismisses the sheet so the same URL
    /// can be replayed later.
    private var isDeepLinkScanPresented: Binding<Bool> {
        Binding(
            get: {
                hasOnboarded
                    && !showsOnboardingPaywall
                    && deepLinks.pending == .scan
            },
            set: { newValue in
                if !newValue { deepLinks.pending = nil }
            }
        )
    }

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
                    onFirstSaveMomentFinished: presentPaywallAfterFirstSave
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
                        if isPresented {
                            // The front-door gate is the paywall for this
                            // moment. Consume the one-time Wallet soft prompt
                            // so Add to Wallet cannot raise a second paywall.
                            UserDefaults.standard.set(true, forKey: "kept.hasShownPaywallAfterFirstPass")
                        } else {
                            // Stamp when the gate dismisses so subsequent
                            // launches never re-show it (buy, trial, or skip).
                            hasSeenOnboardingPaywall = true
                        }
                    }
                    // Deep-link CaptureView (from the App Store In-App Event
                    // Open, or a universal link / custom-scheme tap). Waits
                    // out onboarding + paywall gates, then presents on top
                    // of Library. Sits parallel to LibraryView's own capture
                    // sheet — in practice only one path fires at a time.
                    .sheet(isPresented: isDeepLinkScanPresented) {
                        CaptureView()
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
        // Custom-scheme drop-in (`kept://scan`) fires on both cold-start
        // (once the scene is up) and warm-open.
        .onOpenURL { url in deepLinks.handle(url) }
        // Universal-link drop-in — iOS fires this activity whenever a
        // `https://getkept.xyz/app/*` link opens the app: App Store event
        // Open, Notes long-press, Safari smart banner, share sheet. The
        // string literal matches Foundation's C constant since Swift
        // doesn't expose `NSUserActivityTypeBrowseWeb` as a symbol.
        .onContinueUserActivity("NSUserActivityTypeBrowseWeb") { activity in
            if let url = activity.webpageURL { deepLinks.handle(url) }
        }
        // Apply user's in-app text-size override at the root so every
        // text token adopts it. When set to `.system` this is a no-op
        // and Kept keeps following iOS's Dynamic Type setting.
        .keptTextSize(userTextSize)
        .preferredColorScheme(appearance.colorScheme)
        .tint(darkAccent.tint)
    }

    /// Front-door paywall after the first save, whether or not the payoff
    /// sheet was shown. Not after onboarding.
    ///
    /// Called only from a capture or payoff `onDismiss`, after that sheet
    /// has fully gone. The cover is not presented while the sheet is up.
    /// Returns whether the paywall cover was presented, so the library can
    /// hold the notification prompt until the cover dismisses.
    private func presentPaywallAfterFirstSave(_ event: OnboardingPaywallPolicy.Event) -> Bool {
        guard OnboardingPaywallPolicy.trigger(
            for: event,
            hasSeenPaywall: hasSeenOnboardingPaywall
        ) == .showPaywall else { return false }
        showsOnboardingPaywall = true
        return true
    }
}

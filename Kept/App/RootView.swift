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
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw: String = AppearancePreference.system.rawValue
    @AppStorage(SettingsKeys.darkAccent) private var darkAccentRaw: String = DarkAccentPreference.midnight.rawValue
    @AppStorage("kept.textSize") private var textSizeRaw: String = KeptTextSize.system.rawValue
    @State private var openCaptureAfterOnboarding = false
    @State private var isSplashShowing = true

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
                        }
                        // Force at the presentation site so the status bar style
                        // takes it (dark text on white background). Applying only
                        // inside OnboardingView leaves the status bar governed by
                        // the presenting scene's colorScheme, which stays dark in
                        // system-dark mode.
                        .preferredColorScheme(.light)
                        // Belt-and-braces: keep the status bar visible even if
                        // any nested view accidentally sets .persistentSystemOverlays(.hidden).
                        .persistentSystemOverlays(.visible)
                    }
                    .sheet(isPresented: $openCaptureAfterOnboarding) {
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
        // Apply user's in-app text-size override at the root so every
        // text token adopts it. When set to `.system` this is a no-op
        // and Kept keeps following iOS's Dynamic Type setting.
        .keptTextSize(userTextSize)
        .preferredColorScheme(appearance.colorScheme)
        .tint(darkAccent.tint)
    }
}

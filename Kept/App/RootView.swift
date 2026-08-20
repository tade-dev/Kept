import SwiftUI

/// Presents the library. When the user hasn't onboarded, overlays onboarding full-screen.
/// If step 4 was "Yes, a few", opens capture immediately after the cover dismisses.
struct RootView: View {
    @AppStorage(SettingsKeys.hasOnboarded) private var hasOnboarded: Bool = false
    @State private var openCaptureAfterOnboarding = false

    var body: some View {
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
    }
}

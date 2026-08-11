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
            }
            .sheet(isPresented: $openCaptureAfterOnboarding) {
                CaptureView()
            }
    }
}

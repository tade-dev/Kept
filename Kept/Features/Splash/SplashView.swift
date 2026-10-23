import SwiftUI

/// First screen the user sees on cold launch. The stacked seal + wordmark
/// lockup springs up from below the safe area and settles at centre, holds
/// for ~1.5s, then the parent fades this out and reveals the real content
/// (LibraryView or Onboarding).
///
/// Owns none of its own timing beyond the entrance animation — the parent
/// (`RootView`) controls when to dismiss so the whole splash-to-content
/// choreography is coordinated in one place.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didLand = false

    var body: some View {
        ZStack {
            // Paper background. Matches the onboarding aesthetic so the
            // splash-to-Welcome transition doesn't flash different bgs.
            Color(uiColor: .systemBackground)

            Image("KeptStacked")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 180)
                .foregroundStyle(.primary)
                .accessibilityLabel("Kept")
                // Spring in from below the safe area. Bounces gently on
                // landing — the "here" moment.
                .offset(y: didLand ? 0 : 500)
                .opacity(didLand ? 1 : 0)
        }
        // Lift ignoresSafeArea to the ZStack so the Image centres against
        // the physical display, not the shrunken safe area. Fixes the
        // off-centre logo on iPhone Duo (hinge-reserved region) and any
        // other arrangement that insets the safe area.
        .ignoresSafeArea()
        .task { await runEntrance() }
    }

    private func runEntrance() async {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.35)) { didLand = true }
            return
        }
        // Tiny delay so the launch-image → SwiftUI handoff completes
        // before we start animating (otherwise the first frame can look
        // teleported).
        try? await Task.sleep(for: .milliseconds(60))
        withAnimation(.spring(response: 0.85, dampingFraction: 0.62)) {
            didLand = true
        }
    }
}

#Preview {
    SplashView()
}

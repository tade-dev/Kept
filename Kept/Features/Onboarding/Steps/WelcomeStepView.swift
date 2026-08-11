import SwiftUI

/// Step 0 — video, title, subtitle. The Get Started button is rendered by OnboardingView.
struct WelcomeStepView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = Reveal()

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: Spacing.sm)

            DemoVideoView(resourceName: "onboarding-demo")
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Spacing.lg)
                .scaleEffect(appeared.demo ? 1 : 0.94)
                .opacity(appeared.demo ? 1 : 0)

            VStack(spacing: Spacing.sm) {
                Text("Every receipt is a promise.")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(appeared.headline ? 1 : 0)
                    .offset(y: appeared.headline ? 0 : 14)

                Text("Kept remembers when it expires.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(appeared.subhead ? 1 : 0)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.md)
        }
        .task { await runEntrance() }
    }

    private func runEntrance() async {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) {
                appeared = .all
            }
            return
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            appeared.demo = true
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            appeared.headline = true
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        withAnimation(.easeOut(duration: 0.32)) {
            appeared.subhead = true
        }
    }
}

private struct Reveal: Equatable {
    var demo = false
    var headline = false
    var subhead = false

    static let all = Reveal(demo: true, headline: true, subhead: true)
}

#Preview {
    WelcomeStepView()
}

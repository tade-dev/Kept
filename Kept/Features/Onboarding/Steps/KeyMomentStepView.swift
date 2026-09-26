import SwiftUI

/// Scripted story: question, then Covered, then proof. Replaces the old
/// countdown that landed on Expired. The CTA lives in `OnboardingView`.
struct KeyMomentStepView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var coordinator: OnboardingCoordinator

    @State private var resolved = false
    @State private var showsPayoff = false

    private var prefersStatic: Bool {
        reduceMotion
            || coordinator.hasPlayedKeyMoment
            || UIAccessibility.isVoiceOverRunning
    }

    private var showsResolved: Bool { resolved || prefersStatic }
    private var showsPayoffLine: Bool { showsPayoff || prefersStatic }

    var body: some View {
        OnboardingScaffold(
            titleText: Text(OnboardingCopy.keyMomentContext)
                .font(.keptHeadline)
                .foregroundStyle(.secondary)
            + Text(verbatim: "\n")
            + Text(OnboardingCopy.keyMomentQuestion)
                .font(KeptFont.sans(36, weight: .bold, relativeTo: .largeTitle))
                .foregroundStyle(.primary),
            stylesTitle: false
        ) {
            ViewThatFits(in: .vertical) {
                momentContent
                ScrollView { momentContent }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: resolved)
        .task { await play() }
    }

    private var momentContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            CoverageCard(
                state: KeyMomentScript.phase,
                merchant: KeyMomentScript.merchant,
                item: KeyMomentScript.item,
                daysRemaining: KeyMomentScript.daysRemaining,
                isResolved: showsResolved,
                proof: .init(
                    receiptImage: DemoAssets.receiptJPEG,
                    showsClaimPackReady: true
                ),
                usesAccessibleCovered: true,
                spokenLeadIn: String(localized: "Example", comment: "VoiceOver lead-in for the scripted key-moment card")
            )

            Text(OnboardingCopy.keyMomentPayoff)
                .font(.keptTitle3)
                .opacity(showsPayoffLine ? 1 : 0)
                .offset(y: showsPayoffLine || reduceMotion ? 0 : 8)
                .accessibilityHidden(!showsPayoffLine)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func play() async {
        // Static viewers already see the final frame via `prefersStatic`.
        // Leave `resolved` false so the resolve haptic does not fire.
        if prefersStatic {
            coordinator.hasPlayedKeyMoment = true
            return
        }

        try? await Task.sleep(for: .milliseconds(KeyMomentScript.questionMilliseconds))
        guard !Task.isCancelled else { return }
        withAnimation(.snappy(duration: 0.45)) {
            resolved = true
        }

        try? await Task.sleep(for: .milliseconds(KeyMomentScript.payoffMilliseconds))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.30)) {
            showsPayoff = true
        }
        coordinator.hasPlayedKeyMoment = true
    }
}

#Preview {
    KeyMomentStepView(coordinator: OnboardingCoordinator())
}

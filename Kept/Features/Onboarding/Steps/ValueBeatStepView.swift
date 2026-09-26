import SwiftUI

/// Resting state of the key-moment animation. The card resolves to
/// Covered · N days left and never lands on Expired.
enum ValueBeatScript {
    static let restingPhase = SampleCoverageCard.phase
    static let restingDays = SampleCoverageCard.daysRemaining

    /// Day counts the card climbs through. Each stays in the covered range;
    /// the last value is the rest state.
    static var ticks: [Int] {
        [30, 90, 180, restingDays]
    }
}

struct ValueBeatStepView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var coordinator: OnboardingCoordinator

    @State private var phase: CoverageCard.Phase = ValueBeatScript.restingPhase
    @State private var daysRemaining: Int = ValueBeatScript.ticks.first ?? ValueBeatScript.restingDays
    @State private var showProof = false

    var body: some View {
        OnboardingScaffold(
            // Copy: OnboardingCopy.valueBeatTitle (DESIGN-PENDING)
            title: OnboardingCopy.valueBeatTitle
        ) {
            VStack(spacing: Spacing.lg) {
                Spacer(minLength: 0)

                CoverageCard(
                    state: phase,
                    merchant: SampleCoverageCard.merchant,
                    item: SampleCoverageCard.item,
                    daysRemaining: daysRemaining,
                    emphasized: true,
                    proof: showProof ? .illustrative : nil
                )

                Spacer(minLength: 0)

                Text("Tap to continue")
                    .font(.keptFootnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, Spacing.md)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { coordinator.advance() }
        .task { await runAnimation() }
    }

    /// Resolves to Covered · N days left. Does not transition to `.expired`.
    private func runAnimation() async {
        if reduceMotion {
            phase = ValueBeatScript.restingPhase
            daysRemaining = ValueBeatScript.restingDays
            showProof = true
            return
        }

        phase = ValueBeatScript.restingPhase
        daysRemaining = ValueBeatScript.ticks.first ?? ValueBeatScript.restingDays
        showProof = false

        for value in ValueBeatScript.ticks {
            if Task.isCancelled { return }
            withAnimation(.snappy(duration: 0.35)) {
                phase = ValueBeatScript.restingPhase
                daysRemaining = value
            }
            try? await Task.sleep(nanoseconds: 420_000_000)
        }

        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            showProof = true
        }
    }
}

#Preview {
    ValueBeatStepView(coordinator: OnboardingCoordinator())
}

import SwiftUI

struct ValueBeatStepView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var coordinator: OnboardingCoordinator

    @State private var phase: CoverageCard.Phase = .covered
    @State private var daysRemaining: Int = 14

    var body: some View {
        OnboardingScaffold(
            title: "Your headphones die in month 13. The warranty ran 12."
        ) {
            VStack(spacing: Spacing.lg) {
                Spacer(minLength: 0)

                CoverageCard(
                    state: phase,
                    merchant: "Sony",
                    item: "WH-1000XM5 Headphones",
                    daysRemaining: daysRemaining,
                    emphasized: true
                )

                Spacer(minLength: 0)

                Text("Tap to continue")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, Spacing.md)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { coordinator.advance() }
        .task { await runLoop() }
    }

    private func runLoop() async {
        if reduceMotion {
            phase = .endingSoon
            daysRemaining = 3
            return
        }

        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.6)) {
                phase = .covered
                daysRemaining = 14
            }
            try? await Task.sleep(nanoseconds: 900_000_000)

            for value in stride(from: 13, through: 3, by: -1) {
                withAnimation(.snappy(duration: 0.12)) {
                    daysRemaining = value
                }
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            withAnimation(.easeInOut(duration: 0.5)) {
                phase = .endingSoon
            }
            try? await Task.sleep(nanoseconds: 900_000_000)

            for value in stride(from: 2, through: 0, by: -1) {
                withAnimation(.snappy(duration: 0.15)) {
                    daysRemaining = value
                }
                try? await Task.sleep(nanoseconds: 140_000_000)
            }
            withAnimation(.easeInOut(duration: 0.6)) {
                phase = .expired
            }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
        }
    }
}

#Preview {
    ValueBeatStepView(coordinator: OnboardingCoordinator())
}

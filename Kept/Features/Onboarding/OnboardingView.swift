import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var coordinator = OnboardingCoordinator()
    @State private var finishedTick = 0

    /// Fires when the last step completes. Bool = whether the user said "Yes, a few".
    let onFinish: (Bool) -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                headerArea

                stepBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ctaArea
            }
        }
        .animation(stepAnimation, value: coordinator.step)
        .sensoryFeedback(.selection, trigger: coordinator.step)
        .sensoryFeedback(.success, trigger: finishedTick)
    }

    // MARK: - Fixed header (chrome only — only the progress bar animates on step change)

    @ViewBuilder
    private var headerArea: some View {
        if coordinator.step.showsChrome {
            OnboardingChrome(
                fraction: coordinator.step.progressFraction ?? 0,
                onBack: { coordinator.back() }
            )
            .padding(.top, Spacing.sm)
            .transition(.opacity)
        } else {
            Spacer().frame(height: Spacing.md)
        }
    }

    // MARK: - Sliding step body

    private var stepBody: some View {
        Group {
            currentStep
        }
        .id(coordinator.step)
        .transition(stepTransition)
    }

    @ViewBuilder
    private var currentStep: some View {
        switch coordinator.step {
        case .welcome:
            WelcomeStepView()
        case .keyMoment:
            KeyMomentStepView(coordinator: coordinator)
        case .privacy:
            PrivacyStepView()
        case .existingReceipts:
            ExistingReceiptsStepView(coordinator: coordinator)
        case .notifications:
            NotificationsStepView()
        }
    }

    // MARK: - Fixed CTA (animates in/out per step)

    @ViewBuilder
    private var ctaArea: some View {
        Group {
            switch coordinator.step {
            case .welcome:
                singleCTA(OnboardingCopy.welcomeCTA, enabled: true) { coordinator.advance() }
            case .keyMoment:
                singleCTA("Continue", enabled: true) { coordinator.advance() }
            case .privacy:
                singleCTA("Continue", enabled: true) { coordinator.advance() }
            case .notifications:
                notificationsCTA
            case .existingReceipts:
                EmptyView()
            }
        }
        .transition(ctaTransition)
    }

    private func singleCTA(_ label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.keptHeadline)
                .foregroundStyle(KeptColor.adaptiveOnInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md + 2)
                .background(Capsule().fill(KeptColor.adaptiveInk))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    private var notificationsCTA: some View {
        VStack(spacing: Spacing.sm) {
            Button {
                // The system prompt is not raised during onboarding. It is
                // requested once, after the first save, and only after the
                // payoff sheet and front-door paywall have left the screen.
                finishOnboarding()
            } label: {
                Text("Enable notifications")
                    .font(.keptHeadline)
                    .foregroundStyle(KeptColor.adaptiveOnInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md + 2)
                    .background(Capsule().fill(KeptColor.adaptiveInk))
            }

            Button("Not now") { finishOnboarding() }
                .font(KeptFont.sans(15, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    private func finishOnboarding() {
        coordinator.finish()
        finishedTick &+= 1
        onFinish(coordinator.result.hasExistingReceipts)
    }

    // MARK: - Motion

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private var ctaTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    private var stepAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.32)
    }
}

#Preview {
    OnboardingView { _ in }
}

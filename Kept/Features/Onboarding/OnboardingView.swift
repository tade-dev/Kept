import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var coordinator = OnboardingCoordinator()
    @State private var isRequestingAuth = false
    @State private var finishedTick = 0

    /// Fires when step 7 completes. Bool = whether the user said "Yes, a few".
    let onFinish: (Bool) -> Void

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

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
        case .categories:
            CategoriesStepView(coordinator: coordinator)
        case .leadTimes:
            LeadTimesStepView(coordinator: coordinator)
        case .valueBeat:
            ValueBeatStepView(coordinator: coordinator)
        case .privacy:
            PrivacyStepView(coordinator: coordinator)
        case .existingReceipts:
            ExistingReceiptsStepView(coordinator: coordinator)
        case .notifications:
            NotificationsStepView(coordinator: coordinator)
        case .settingUp:
            SettingUpStepView {
                coordinator.finish()
                finishedTick &+= 1
                onFinish(coordinator.result.hasExistingReceipts)
            }
        }
    }

    // MARK: - Fixed CTA (animates in/out per step)

    @ViewBuilder
    private var ctaArea: some View {
        Group {
            switch coordinator.step {
            case .welcome:
                singleCTA("Get Started", enabled: true) { coordinator.advance() }
            case .categories, .leadTimes:
                singleCTA("Continue", enabled: coordinator.canAdvance) { coordinator.advance() }
            case .privacy:
                singleCTA("Continue", enabled: true) { coordinator.advance() }
            case .notifications:
                notificationsCTA
            case .valueBeat, .existingReceipts, .settingUp:
                EmptyView()
            }
        }
        .transition(ctaTransition)
    }

    /// Negative on Privacy so the button pulls up into the step body and Z-covers the
    /// bottom of the assurances card — stacked look, button stays fully rounded.
    private var ctaTopSpacing: CGFloat {
        coordinator.step == .privacy ? -32 : Spacing.sm
    }

    private func singleCTA(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .foregroundStyle(KeptColor.onInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md + 2)
                .background(Capsule().fill(KeptColor.ink))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .padding(.horizontal, Spacing.lg)
        .padding(.top, ctaTopSpacing)
        .padding(.bottom, Spacing.md)
    }

    private var notificationsCTA: some View {
        VStack(spacing: Spacing.sm) {
            Button {
                Task { await requestAuth() }
            } label: {
                HStack {
                    if isRequestingAuth {
                        ProgressView().tint(KeptColor.onInk)
                    } else {
                        Text("Enable notifications")
                            .font(.headline)
                    }
                }
                .foregroundStyle(KeptColor.onInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md + 2)
                .background(Capsule().fill(KeptColor.ink))
            }
            .disabled(isRequestingAuth)

            Button("Not now") { coordinator.advance() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    private func requestAuth() async {
        isRequestingAuth = true
        _ = await CoverageNotificationScheduler.requestAuthorizationIfNeeded()
        isRequestingAuth = false
        coordinator.advance()
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

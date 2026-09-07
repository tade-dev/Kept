import SwiftUI

struct ExistingReceiptsStepView: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            title: "Got receipts for things you already own?"
        ) {
            VStack(spacing: Spacing.sm) {
                OnboardingOptionRow(
                    icon: "doc.on.doc",
                    title: "Yes, a few",
                    subtitle: String(localized: "Open the camera when I'm done."),
                    selected: false
                ) {
                    coordinator.result.hasExistingReceipts = true
                    coordinator.advance()
                }

                OnboardingOptionRow(
                    icon: "sparkles",
                    title: "No, starting fresh",
                    subtitle: String(localized: "I'll scan as I buy from here."),
                    selected: false
                ) {
                    coordinator.result.hasExistingReceipts = false
                    coordinator.advance()
                }

                Spacer(minLength: 0)
            }
        }
    }
}

#Preview {
    ExistingReceiptsStepView(coordinator: OnboardingCoordinator())
}

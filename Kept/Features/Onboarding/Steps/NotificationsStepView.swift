import SwiftUI

/// Last onboarding step. Enable / Not now buttons are rendered by OnboardingView,
/// which finishes the flow without raising the system prompt.
struct NotificationsStepView: View {
    var body: some View {
        OnboardingScaffold(
            titleText: Text("We'll tell you 30 and 7 days before a warranty ends."),
            subtitleText: Text("No marketing, no upsell. Only the countdown.")
        ) {
            VStack {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 180, height: 180)

                    Image(systemName: "bell.badge")
                        .font(KeptFont.sans(78, weight: .regular, relativeTo: .largeTitle))
                        .foregroundStyle(.primary)
                }

                Spacer()
            }
        }
    }
}

#Preview {
    NotificationsStepView()
}

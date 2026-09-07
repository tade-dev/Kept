import SwiftUI

/// Step 6 — the ask is framed by the user's lead-time choice. Enable / Not now buttons
/// are rendered by OnboardingView so this step only owns the icon + copy.
struct NotificationsStepView: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            titleText: Text(verbatim: headline),
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

    private var headline: String {
        let sorted = coordinator.result.warningLeadTimes.sorted()
        switch sorted.count {
        case 1:
            return String(
                localized: "We'll tell you \(sorted[0]) days before cover ends.",
                comment: "Onboarding notifications summary with a single lead day; needs plural handling"
            )
        case 2:
            return String(
                localized: "We'll tell you \(sorted[0]) and \(sorted[1]) days before cover ends.",
                comment: "Onboarding notifications summary with two lead days"
            )
        default:
            let head = sorted.dropLast().map(String.init).joined(separator: ", ")
            let tail = sorted.last.map(String.init) ?? ""
            return String(
                localized: "We'll tell you \(head), and \(tail) days before cover ends.",
                comment: "Onboarding notifications summary with three or more lead days"
            )
        }
    }
}

#Preview {
    NotificationsStepView(coordinator: OnboardingCoordinator())
}

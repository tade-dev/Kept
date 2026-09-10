import SwiftUI

struct LeadTimesStepView: View {
    @Bindable var coordinator: OnboardingCoordinator

    private let options: [Int] = [30, 14, 7]

    var body: some View {
        OnboardingScaffold(
            title: "When should we warn you?",
            subtitle: "Pick as many as you like."
        ) {
            VStack(spacing: Spacing.sm) {
                ForEach(options, id: \.self) { day in
                    OnboardingOptionRow(
                        icon: symbol(for: day),
                        title: "\(day) days before",
                        subtitle: subtitle(for: day),
                        selected: coordinator.result.warningLeadTimes.contains(day)
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            coordinator.toggleLead(day)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func symbol(for day: Int) -> String {
        switch day {
        case 30: "calendar"
        case 14: "clock"
        default: "bolt"
        }
    }

    private func subtitle(for day: Int) -> String {
        switch day {
        case 30: String(localized: "Plenty of time to book a repair.")
        case 14: String(localized: "Enough time to act.")
        default: String(localized: "Last chance.")
        }
    }
}

#Preview {
    LeadTimesStepView(coordinator: OnboardingCoordinator())
}

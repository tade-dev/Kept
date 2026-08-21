import SwiftUI

struct CategoriesStepView: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            title: "What do you want to keep track of?",
            subtitle: "Pick any that apply."
        ) {
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    ForEach(TrackedCategory.allCases) { category in
                        OnboardingOptionRow(
                            icon: category.symbol,
                            title: category.label,
                            subtitle: category.subtitle,
                            selected: isSelected(category)
                        ) {
                            withAnimation(.snappy(duration: 0.2)) {
                                coordinator.toggle(category)
                            }
                        }
                    }
                }
            }
        }
    }

    private func isSelected(_ category: TrackedCategory) -> Bool {
        category == .everything
            ? coordinator.isEverythingSelected
            : coordinator.result.categories.contains(category)
    }
}

private extension TrackedCategory {
    var subtitle: String {
        switch self {
        case .electronics: "Phones, laptops, headphones."
        case .appliances:  "Kettles, blenders, washers."
        case .furniture:   "Sofas, desks, storage."
        case .clothing:    "Return windows, not warranties."
        case .everything:  "Includes all four."
        }
    }
}

#Preview {
    CategoriesStepView(coordinator: OnboardingCoordinator())
}

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
        case .electronics: String(localized: "Phones, laptops, headphones.")
        case .appliances:  String(localized: "Kettles, blenders, washers.")
        case .furniture:   String(localized: "Sofas, desks, storage.")
        case .clothing:    String(localized: "Return windows, not warranties.")
        case .everything:  String(localized: "Includes all four.")
        }
    }
}

#Preview {
    CategoriesStepView(coordinator: OnboardingCoordinator())
}

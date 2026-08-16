import SwiftUI

/// Full-width tappable row card. Selected = ink fill + onInk text; unselected = secondary bg + primary text.
/// Icon renders inside a white circle so it reads over either background without recoloring.
struct OnboardingOptionRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(KeptFont.sans(18, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.keptTitle3)
                        .foregroundStyle(selected ? KeptColor.onInk : .primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.keptSubheadline)
                            .foregroundStyle(selected ? KeptColor.onInk.opacity(0.75) : .secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected ? KeptColor.ink : Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

#Preview {
    VStack(spacing: 12) {
        OnboardingOptionRow(icon: "laptopcomputer", title: "Electronics", subtitle: "Phones, laptops, headphones.", selected: false, onTap: {})
        OnboardingOptionRow(icon: "washer", title: "Appliances", subtitle: "Kettles, blenders, washers.", selected: true, onTap: {})
    }
    .padding()
}

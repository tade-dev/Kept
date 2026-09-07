import SwiftUI

/// Full-width tappable row card. Selected = ink fill + onInk text; unselected = secondary bg + primary text.
/// Icon renders inside a white circle so it reads over either background without recoloring.
struct OnboardingOptionRow: View {
    let icon: String
    /// Row title — a catalog key. Pass a literal at the call site so SwiftUI
    /// resolves it against the localised strings.
    let title: LocalizedStringKey
    /// Row subtitle. Often built from a dynamic enum ("Electronics" →
    /// "Phones, laptops, headphones.") that's already pre-localised via
    /// `String(localized:)`, so callers hand us a plain string and we
    /// display it verbatim rather than treating it as another key.
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
                    .background(Circle().fill(KeptColor.adaptiveOnInk))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.keptTitle3)
                        .foregroundStyle(selected ? KeptColor.adaptiveOnInk : .primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.keptSubheadline)
                            .foregroundStyle(selected ? KeptColor.adaptiveOnInk.opacity(0.75) : .secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected ? KeptColor.adaptiveInk : Color(.secondarySystemBackground))
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

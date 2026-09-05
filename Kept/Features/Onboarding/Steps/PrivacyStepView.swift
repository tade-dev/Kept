import SwiftUI

/// Step 4 — Privacy reassurance. Assurances card renders as the footer with flat bottom
/// corners so it visually joins the Continue button below.
struct PrivacyStepView: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            title: "Your receipts stay yours.",
            subtitle: "Kept was built for people who don't want another app sitting on their private stuff."
        ) {
            VStack {
                Spacer()
                haloSymbol
                Spacer()
            }
        } footer: {
            assurances
        }
    }

    // MARK: - Halo

    private var haloSymbol: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            KeptColor.covered.opacity(0.20),
                            KeptColor.endingSoon.opacity(0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 200, height: 200)

            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 156, height: 156)
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )

            Image(systemName: "hand.raised.fill")
                .font(KeptFont.sans(60, weight: .regular, relativeTo: .largeTitle))
                .foregroundStyle(.primary)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Assurances card (banner-style — flat bottom to fuse with button)

    private var assurances: some View {
        VStack(spacing: 0) {
            row(
                symbol: "camera",
                title: "Photos never leave your phone",
                subtitle: "Receipt images live only on this device."
            )
            divider
            row(
                symbol: "eye.slash",
                title: "No ads, no tracking, no sale",
                subtitle: "Kept doesn't watch you. There's nothing to sell."
            )
            divider
            row(
                symbol: "trash",
                title: "Delete everything, anytime",
                subtitle: "Settings → Data → Delete all data."
            )
        }
        .padding(Spacing.md)
        // Extra bottom padding so the assurance rows aren't hidden when the CTA button
        // pulls up and Z-covers this card's bottom.
        .padding(.bottom, Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var divider: some View {
        Divider().padding(.vertical, Spacing.sm)
    }

    private func row(symbol: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(KeptFont.sans(16, weight: .semibold, relativeTo: .callout))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KeptFont.sans(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.keptCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    PrivacyStepView(coordinator: OnboardingCoordinator())
}

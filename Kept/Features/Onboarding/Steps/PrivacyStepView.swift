import SwiftUI

/// Privacy reassurance. The step title and first row match extraction:
/// the worker receives OCR text, not the photo. Photos still sync to the
/// user's own iCloud; that fact lives in Settings, not in this row.
/// Rows 2 and 3 are the existing assurances.
struct PrivacyStepView: View {
    var body: some View {
        OnboardingScaffold(
            title: OnboardingCopy.privacyTitle,
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

    private var assurances: some View {
        VStack(spacing: 0) {
            row(
                symbol: "photo",
                title: OnboardingCopy.privacyTitle,
                subtitle: OnboardingCopy.privacyLine
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
        .padding(.bottom, Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var divider: some View {
        Divider().padding(.vertical, Spacing.sm)
    }

    private func row(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
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
    PrivacyStepView()
}

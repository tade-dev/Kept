import SwiftUI

/// Front-door monetisation flow presented once, immediately after the
/// onboarding cover dismisses. Owns the choreography between three states:
///
///   .paywall   → PaywallView(reason: .onboardingEntry) with a visible
///                "Continue with limited version" secondary button.
///   .explainer → FreeTierExplainerSheet showing what Free actually gets
///                + a persistent "Start 7-day free trial" CTA that can
///                bounce back to .paywall without dismissing anything.
///
/// Either purchasing Pro OR tapping "Continue" on the explainer dismisses
/// the whole gate. RootView sets a UserDefaults flag on first present so
/// the gate never fires again — post-install conversion happens on the
/// per-feature paywalls (wallet pass add, claim-pack export, 6th save on
/// free, Settings › Upgrade).
struct OnboardingPaywallGate: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionAccess.self) private var subscription

    private enum Stage: Equatable { case paywall, explainer }
    @State private var stage: Stage = .paywall

    var body: some View {
        Group {
            switch stage {
            case .paywall:
                PaywallView(
                    reason: .onboardingEntry,
                    onSkip: { withAnimation(.snappy(duration: 0.28)) { stage = .explainer } }
                )
            case .explainer:
                FreeTierExplainerSheet(
                    onStartTrial: { withAnimation(.snappy(duration: 0.28)) { stage = .paywall } },
                    onContinue: { dismiss() }
                )
            }
        }
        // Purchase completed inside the paywall → close the whole gate so
        // the user lands in the Library as a fresh Pro user.
        .onChange(of: subscription.isPro) { _, nowPro in
            if nowPro { dismiss() }
        }
    }
}

/// Post-skip explainer. Kept lockup up top, honest feature grid (what's
/// included on Free vs Pro), and a persistent trial CTA at the bottom.
/// Kept deliberately airy — the moment is "I said no, remind me what
/// I'm walking away from" so the sheet answers plainly without pressure.
struct FreeTierExplainerSheet: View {
    var onStartTrial: () -> Void
    var onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                        .padding(.top, 24)

                    featureGrid
                        .padding(.horizontal, 20)

                    Spacer(minLength: 16)
                }
                .padding(.bottom, 180)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { ctaBar }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            Image("KeptLockup")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
                .accessibilityHidden(true)

            Text("You're on Kept Free")
                .font(KeptFont.sans(28, weight: .bold, relativeTo: .title))
                .multilineTextAlignment(.center)

            Text("Here's what you can do without Pro — and what unlocks with a trial.")
                .font(.keptFootnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Feature grid

    private var featureGrid: some View {
        VStack(spacing: 12) {
            planCard(
                title: String(localized: "Kept Free"),
                tint: Color(.tertiarySystemGroupedBackground),
                rows: [
                    .init(icon: "checkmark", included: true,  text: String(localized: "Scan and save up to 5 receipts")),
                    .init(icon: "checkmark", included: true,  text: String(localized: "Warranty & return deadline reminders")),
                    .init(icon: "checkmark", included: true,  text: String(localized: "Category, price, and merchant capture"))
                ]
            )

            planCard(
                title: String(localized: "Kept Pro"),
                tint: KeptColor.adaptiveInk.opacity(0.08),
                rows: [
                    .init(icon: "sparkles",       included: true, text: String(localized: "Unlimited receipts")),
                    .init(icon: "wallet.pass",    included: true, text: String(localized: "Add receipts to Apple Wallet")),
                    .init(icon: "doc.text",       included: true, text: String(localized: "One-tap Claim Pack export")),
                    .init(icon: "cpu",            included: true, text: String(localized: "Pro-tier extraction model")),
                    .init(icon: "person.2",       included: true, text: String(localized: "Family Sharing"))
                ]
            )
        }
    }

    private struct FeatureRow: Identifiable {
        let id = UUID()
        var icon: String
        var included: Bool
        var text: String
    }

    private func planCard(title: String, tint: Color, rows: [FeatureRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.keptHeadline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 22)
                            .foregroundStyle(row.included ? Color.accentColor : Color.secondary.opacity(0.6))
                        Text(row.text)
                            .font(.keptBody)
                            .foregroundStyle(row.included ? .primary : .secondary)
                            .strikethrough(!row.included, color: .secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint)
        )
    }

    // MARK: - CTA bar

    private var ctaBar: some View {
        VStack(spacing: 10) {
            Button(action: onStartTrial) {
                Text("Start 7-day free trial")
                    .font(.keptHeadline)
                    .foregroundStyle(KeptColor.adaptiveOnInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(KeptColor.adaptiveInk))
            }
            .buttonStyle(.plain)

            Button("Continue with Free", action: onContinue)
                .font(KeptFont.sans(15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(
            Color(.systemGroupedBackground)
                .shadow(color: .black.opacity(0.04), radius: 6, y: -1)
        )
    }
}

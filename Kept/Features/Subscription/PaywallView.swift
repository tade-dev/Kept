import SwiftUI

/// IFTTT-inspired paywall — brand + Pro badge at top, two-card price picker,
/// clean checklist of features, big pill CTA, trial fine print with terms.
///
/// Native chrome (NavigationStack + toolbar close button); custom price cards
/// and checkmarks below.
///
/// Trigger points (see AGENTS.md / Monetisation):
///   1. Attempted 6th save while free
///   2. First successful Wallet pass added (soft prompt with "Not now")
///   3. Manual, from Settings › Account
struct PaywallView: View {
    var reason: Reason = .capReached
    /// Optional escape hatch shown as a secondary button in the CTA bar.
    /// When non-nil, "Continue with limited version" appears below the
    /// primary CTA. Used by the onboarding-entry flow to let the user
    /// bounce out to the free-tier explainer sheet instead of subscribing.
    /// When nil, no skip button appears (default paywall behaviour).
    var onSkip: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionAccess.self) private var subscription

    @State private var selection: Selection = .yearly
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var successTick = 0

    enum Reason: Equatable {
        case capReached
        case firstPassAdded
        case manual
        case claimPack
        /// Front-door paywall shown once after onboarding finishes. Framed
        /// as "try Pro for 7 days" rather than "you hit a wall" — the user
        /// hasn't done anything yet, so the copy needs to invite, not scold.
        case onboardingEntry

        var subtitle: String {
            switch self {
            case .capReached:      String(localized: "You've filled your free five — keep every warranty from here.")
            case .firstPassAdded:  String(localized: "Unlimited receipts, plus the claim pack for the day it matters.")
            case .manual:          String(localized: "Unlimited receipts and the claim pack for the day it matters.")
            case .claimPack:       String(localized: "Export a signed claim pack in one tap. Included with Pro.")
            case .onboardingEntry: String(localized: "Try Kept Pro free for 7 days. Unlimited receipts, Apple Wallet passes, and the claim pack when it matters.")
            }
        }
    }

    private enum Selection: Hashable { case monthly, yearly, lifetime }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let welcomeBackSummary {
                        winBackBanner(summary: welcomeBackSummary)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    brandBlock
                        .padding(.top, 8)

                    Text(reason.subtitle)
                        .font(.keptBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)

                    pricePicker
                        .padding(.horizontal, 20)

                    if subscription.offering?.lifetime != nil {
                        lifetimeCard
                            .padding(.horizontal, 20)
                    }

                    features
                        .padding(.horizontal, 24)

                    Spacer(minLength: 24)
                }
                .padding(.bottom, 160)  // room for the CTA bar
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                // In the onboarding-entry flow the user cannot close via ✕ —
                // they must either start the trial or take the visible skip
                // button in the CTA bar, so the choice is deliberate rather
                // than an accidental swipe-away.
                if onSkip == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(KeptFont.sans(17, weight: .semibold, relativeTo: .body))
                        }
                        .accessibilityLabel("Close")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { ctaBar }
            .alert(
                errorMessage ?? "",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            }
            .sensoryFeedback(.success, trigger: successTick)
            .task { await subscription.refresh() }
        }
    }

    // MARK: - Win-back banner

    /// The best win-back summary across all currently offered packages, or
    /// nil when the customer isn't eligible for any. Non-nil == render the
    /// banner. Rides on the offering's win-back state, so it lights up
    /// automatically the moment RC + ASC surface an eligible offer.
    private var welcomeBackSummary: String? {
        subscription.offering?.yearly?.winBackOffer?.summary
            ?? subscription.offering?.monthly?.winBackOffer?.summary
    }

    private func winBackBanner(summary: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("Welcome back")
                    .font(KeptFont.sans(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(.primary)
                Text(summary)
                    .font(.keptCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Brand block

    /// Wordmark + PRO pill, composed programmatically. Uses the template-
    /// friendly `KeptLockup` asset (single-colour, tints with the current
    /// foreground) instead of the fixed-colour `KeptProLockup` PNG which
    /// disappears against a dark canvas. PRO pill uses the same
    /// `adaptiveInk` slab language as the CTA below for visual cohesion.
    private var brandBlock: some View {
        HStack(spacing: 10) {
            Image("KeptLockup")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 40)
                .foregroundStyle(.primary)

            Text("PRO")
                .font(KeptFont.sans(12, weight: .bold, relativeTo: .caption))
                .kerning(0.8)
                .foregroundStyle(KeptColor.adaptiveOnInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(KeptColor.adaptiveInk))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kept Pro")
        .frame(maxWidth: .infinity)
    }

    // MARK: - Two-card price picker

    private var pricePicker: some View {
        HStack(spacing: 10) {
            priceCard(
                for: .yearly,
                package: subscription.offering?.yearly,
                perLabel: "/year",
                badge: subscription.offering?.yearly?.savingsBadge
                    .map { $0.replacingOccurrences(of: " OFF", with: "") }
            )
            priceCard(
                for: .monthly,
                package: subscription.offering?.monthly,
                perLabel: "/month",
                badge: nil
            )
        }
    }

    private func priceCard(
        for target: Selection,
        package: SubscriptionPackage?,
        perLabel: String,
        badge: String?
    ) -> some View {
        let isSelected = selection == target
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selection = target
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Trial badge sits ABOVE the price so users notice it
                // before selecting — otherwise they miss that yearly is
                // the only plan with a 7-day free trial and pick monthly
                // by default. Only yearly currently ships an intro offer
                // (config verified in ASC), so we only decorate that card.
                if package?.introOfferString != nil {
                    Text("7 days free")
                        .font(KeptFont.sans(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                }

                if let package {
                    Text(package.priceString)
                        .font(KeptFont.sans(26, weight: .bold, relativeTo: .title))
                        .foregroundStyle(isSelected ? Color.primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Text("—")
                        .font(KeptFont.sans(26, weight: .bold, relativeTo: .title))
                        .foregroundStyle(.tertiary)
                        .redacted(reason: .placeholder)
                }

                HStack(spacing: 6) {
                    Text(perLabel)
                        .font(.keptFootnote)
                        .foregroundStyle(.secondary)
                    // Win-back offer takes visual priority over the yearly
                    // SAVE badge — it's a personalised deal for a lapsed
                    // customer, so it should read first.
                    if let winBack = package?.winBackOffer {
                        Text(winBack.summary)
                            .font(KeptFont.sans(11, weight: .bold, relativeTo: .caption2))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.18))
                            )
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else if let badge {
                        Text("SAVE \(badge)")
                            .font(KeptFont.sans(11, weight: .bold, relativeTo: .caption2))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.18))
                            )
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? Color(.secondarySystemGroupedBackground)
                          : Color(.tertiarySystemGroupedBackground))
                    .shadow(
                        color: isSelected ? .black.opacity(0.10) : .clear,
                        radius: 6, y: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? KeptColor.adaptiveInk : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lifetime one-shot

    /// Full-width card for the non-consumable Lifetime option, rendered
    /// underneath the sub row. Distinct layout (horizontal, "BEST VALUE"
    /// chip) so it doesn't compete visually with the yearly SAVE badge.
    private var lifetimeCard: some View {
        let package = subscription.offering?.lifetime
        let isSelected = selection == .lifetime
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selection = .lifetime
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Lifetime")
                            .font(KeptFont.sans(17, weight: .semibold, relativeTo: .headline))
                            .foregroundStyle(isSelected ? Color.primary : .secondary)

                        Text("BEST VALUE")
                            .font(KeptFont.sans(10, weight: .bold, relativeTo: .caption2))
                            .kerning(0.6)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            .foregroundStyle(Color.accentColor)
                    }

                    Text("One-time payment · pay once, own forever")
                        .font(.keptCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                if let package {
                    Text(package.priceString)
                        .font(KeptFont.sans(20, weight: .bold, relativeTo: .title3))
                        .foregroundStyle(isSelected ? Color.primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text("—")
                        .font(KeptFont.sans(20, weight: .bold, relativeTo: .title3))
                        .foregroundStyle(.tertiary)
                        .redacted(reason: .placeholder)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? Color(.secondarySystemGroupedBackground)
                          : Color(.tertiarySystemGroupedBackground))
                    .shadow(
                        color: isSelected ? .black.opacity(0.10) : .clear,
                        radius: 6, y: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? KeptColor.adaptiveInk : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Features

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow("Unlimited receipts")
            featureRow("Claim pack PDF export")
            featureRow("Higher-quality receipt extraction")
            featureRow("Share with up to 5 family members")
            featureRow("Every future Pro feature")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.keptTitle3)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.keptBody)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom CTA bar

    private var ctaBar: some View {
        VStack(spacing: 12) {
            Button(action: { Task { await purchaseSelected() } }) {
                HStack {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(KeptColor.adaptiveOnInk)
                    }
                    Text(ctaLabel)
                        .font(.keptHeadline)
                        .foregroundStyle(KeptColor.adaptiveOnInk)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Capsule().fill(KeptColor.adaptiveInk))
            }
            .buttonStyle(.plain)
            .disabled(isWorking || subscription.offering == nil)

            legalFineprint

            if let onSkip {
                // Visible skip that the App Review team + Apple guideline
                // 3.1.2 both require — no dark-pattern hiding behind a ✕.
                Button("Continue with limited version", action: onSkip)
                    .font(KeptFont.sans(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            HStack(spacing: 20) {
                Button("Restore") { Task { await restore() } }
                if case .firstPassAdded = reason {
                    Button("Not now") { dismiss() }
                }
            }
            .font(.keptFootnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(
            Color(.systemGroupedBackground)
                .shadow(color: .black.opacity(0.04), radius: 6, y: -1)
        )
    }

    private var ctaLabel: String {
        guard currentPackage != nil else { return String(localized: "Continue") }
        if selection == .lifetime { return String(localized: "Get Kept Pro forever") }
        return trialAvailable ? String(localized: "Start 7-day free trial") : String(localized: "Subscribe")
    }

    // Trial ends copy + Terms link — IFTTT-style fine print
    private var legalFineprint: some View {
        VStack(spacing: 4) {
            if selection == .lifetime {
                Text("One-time purchase. No auto-renewal. Family Sharing included.")
                    .font(.keptCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if trialAvailable {
                Text(trialEndsCopy)
                    .font(.keptCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(termsAttributedString)
                .font(.keptCaption)
                .foregroundStyle(.secondary)
                .tint(.primary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }

    /// Markdown-linked terms fine print — the `[Terms of Service](...)`
    /// run gets weight + underline so users clearly read it as tappable
    /// (SwiftUI otherwise renders markdown links as plain tinted text).
    private var termsAttributedString: AttributedString {
        let source = String(localized: "By continuing, you agree to our [Terms of Service](https://getkept.xyz/terms).")
        var attributed = (try? AttributedString(markdown: source)) ?? AttributedString(source)
        for run in attributed.runs where run.link != nil {
            attributed[run.range].underlineStyle = .single
            attributed[run.range].font = .caption.weight(.semibold)
        }
        return attributed
    }

    private var trialEndsCopy: String {
        guard let package = currentPackage else { return "" }
        let end = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        let dateString = end.formatted(date: .long, time: .omitted)
        let priceString = package.priceString
        let periodWord = shortPeriod(from: package.periodString)
        return String(
            localized: "Your trial ends on \(dateString). Afterwards, you will be billed \(priceString) \(periodWord)ly. Cancel anytime before the trial ends at no cost.",
            comment: "Paywall trial-end fine print"
        )
    }

    // MARK: - Helpers

    private var currentPackage: SubscriptionPackage? {
        guard let offering = subscription.offering else { return nil }
        switch selection {
        case .monthly:  return offering.monthly
        case .yearly:   return offering.yearly
        case .lifetime: return offering.lifetime
        }
    }

    private var trialAvailable: Bool {
        currentPackage?.introOfferString != nil
    }

    private func shortPeriod(from full: String) -> String {
        full.replacingOccurrences(of: "per ", with: "")
    }

    // MARK: - Actions

    private func purchaseSelected() async {
        guard let package = currentPackage else {
            errorMessage = "Plans aren't available right now. Pull down to retry."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            // Non-cancelled, non-thrown return = transaction went through.
            // Dismiss without gating on the bool — sandbox propagation of
            // the `pro` entitlement can lag a few seconds, and we don't
            // want the user staring at the paywall with the receipt in hand.
            _ = try await subscription.purchase(package)
            successTick &+= 1
            dismiss()
        } catch SubscriptionServiceError.cancelled {
            // silent
        } catch let error as SubscriptionServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = SubscriptionServiceError.unknown.errorDescription
        }
    }

    private func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let restored = try await subscription.restorePurchases()
            if restored {
                successTick &+= 1
                dismiss()
            } else {
                errorMessage = "No previous purchases were found on this Apple ID."
            }
        } catch let error as SubscriptionServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = SubscriptionServiceError.unknown.errorDescription
        }
    }
}

// MARK: - Environment holder

/// The reactive wrapper the view layer talks to. Owns @Observable state
/// (`isPro`, `offering`, `appUserID`) mirrored from the underlying
/// `SubscriptionService`. Forwards method calls (`purchase`, `restorePurchases`,
/// `refresh`) to the service.
///
/// The service itself is deliberately NOT `@Observable` — Swift's observation
/// macro only registers reads it can see at the concrete type, and can't see
/// through `any SubscriptionService`. So we put the observability HERE and let
/// the service push updates via a callback.
@Observable
@MainActor
final class SubscriptionAccess {
    private(set) var isPro: Bool = false
    private(set) var offering: SubscriptionOffering?
    private(set) var billingIssue: BillingIssue?
    private(set) var proAccessExpiry: ProAccessExpiry?
    private(set) var appUserID: String = ""

    /// Exposed so callers that need the underlying service (e.g. tests) can
    /// reach it, but views should stick to the mirrored properties above.
    let service: any SubscriptionService

    init(service: any SubscriptionService) {
        self.service = service
        self.isPro = service.isPro
        self.offering = service.offering
        self.billingIssue = service.billingIssue
        self.proAccessExpiry = service.proAccessExpiry
        self.appUserID = service.appUserID
        service.onChange = { [weak self] in
            guard let self else { return }
            self.isPro = self.service.isPro
            self.offering = self.service.offering
            self.billingIssue = self.service.billingIssue
            self.proAccessExpiry = self.service.proAccessExpiry
            self.appUserID = self.service.appUserID
        }
    }

    func refresh() async {
        await service.refresh()
    }

    func purchase(_ package: SubscriptionPackage) async throws -> Bool {
        try await service.purchase(package)
    }

    @discardableResult
    func restorePurchases() async throws -> Bool {
        try await service.restorePurchases()
    }

    func grantTrialBoost() async throws {
        try await service.grantTrialBoost()
    }
}

// MARK: - Previews

#Preview("Free — cap reached") {
    PaywallView(reason: .capReached)
        .environment(SubscriptionAccess(service: PreviewSubscriptionService(isPro: false)))
}

#Preview("Free — first pass added") {
    PaywallView(reason: .firstPassAdded)
        .environment(SubscriptionAccess(service: PreviewSubscriptionService(isPro: false)))
}

#Preview("Manual (from Settings)") {
    PaywallView(reason: .manual)
        .environment(SubscriptionAccess(service: PreviewSubscriptionService(isPro: false)))
}

#Preview("Loading offerings") {
    PaywallView(reason: .capReached)
        .environment(SubscriptionAccess(service: PreviewSubscriptionService(isPro: false, offering: nil)))
}

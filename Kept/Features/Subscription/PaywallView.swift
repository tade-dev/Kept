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

    @State private var selection: PaywallPlan = .yearly
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var restoreNotice: String?
    @State private var restoreShouldDismiss = false
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
            case .onboardingEntry: String(localized: "Unlimited receipts, and the claim pack when it matters.")
            }
        }
    }

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

                    features
                        .padding(.horizontal, 24)

                    Spacer(minLength: 24)
                }
                .padding(.bottom, 160)  // room for the CTA bar
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                // Top-leading, visible from the first frame. Onboarding uses
                // it to reach the free-tier explainer; every other reason
                // dismisses.
                ToolbarItem(placement: .cancellationAction) {
                    if let onSkip {
                        Button("Not now", action: onSkip)
                    } else if reason == .firstPassAdded {
                        Button("Not now") { dismiss() }
                    } else {
                        Button("Close") { dismiss() }
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
            .alert(
                restoreNotice ?? "",
                isPresented: Binding(
                    get: { restoreNotice != nil },
                    set: { if !$0 { restoreNotice = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    if restoreShouldDismiss { dismiss() }
                }
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
    /// Yearly only. A monthly win-back is not shown — monthly is not a plan.
    private var welcomeBackSummary: String? {
        subscription.offering?.yearly?.winBackOffer?.summary
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

    // MARK: - Yearly and lifetime, equal weight

    /// Loading shows both peer rows redacted. A failed fetch shows a retry.
    /// A loaded offering shows only yearly and lifetime — monthly is never one of them.
    private var pricePicker: some View {
        let state = PaywallCatalog.offerState(
            offering: subscription.offering,
            loadFailed: subscription.offeringLoadFailed
        )
        return Group {
            switch state {
            case .loading:
                VStack(spacing: 10) {
                    ForEach(PaywallPlan.allCases, id: \.self) { plan in
                        planRow(plan, redacted: true)
                    }
                }
            case .failed:
                VStack(alignment: .leading, spacing: 12) {
                    Text("Couldn't load prices")
                        .font(.keptBody)
                        .foregroundStyle(.primary)
                    Button("Try again") {
                        Task { await subscription.refresh() }
                    }
                    .font(.keptHeadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .empty:
                Text("Plans aren't available right now.")
                    .font(.keptFootnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .ready:
                VStack(spacing: 10) {
                    ForEach(PaywallCatalog.visiblePlans(in: subscription.offering), id: \.self) { plan in
                        planRow(plan, redacted: false)
                    }
                }
            }
        }
    }

    private func planRow(_ plan: PaywallPlan, redacted: Bool) -> some View {
        let package = PaywallCatalog.package(plan, in: subscription.offering)
        let isSelected = !redacted && activeSelection == plan
        let showsTrial = plan == .yearly && PaywallCatalog.hasIntroTrial(package)
        return Button {
            guard !redacted else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selection = plan
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if showsTrial {
                        Text("Free trial")
                            .font(KeptFont.sans(11, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(.secondary)
                    }
                    Text(primaryLine(plan, package: package))
                        .font(KeptFont.sans(17, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let secondary = secondaryLine(plan, package: package) {
                        Text(secondary)
                            .font(.keptFootnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.keptTitle3)
                    .foregroundStyle(isSelected ? KeptColor.adaptiveInk : Color.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? KeptColor.adaptiveInk : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .modifier(PlaceholderRedaction(isActive: redacted))
        }
        .buttonStyle(.plain)
        .disabled(redacted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(planAccessibilityLabel(plan, package: package))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func primaryLine(_ plan: PaywallPlan, package: SubscriptionPackage?) -> String {
        guard let package else { return planTitle(plan) }
        switch plan {
        case .yearly:
            return package.priceString
        case .lifetime:
            return PaywallCatalog.lifetimePriceLine(price: package.priceString)
        }
    }

    private func secondaryLine(_ plan: PaywallPlan, package: SubscriptionPackage?) -> String? {
        switch plan {
        case .yearly:
            guard let package,
                  let count = package.introPeriodCount,
                  let unit = package.introPeriodUnit,
                  PaywallCatalog.hasIntroTrial(package) else { return nil }
            return PaywallCatalog.yearlyTrialLine(count: count, unit: unit, price: package.priceString)
        case .lifetime:
            return String(localized: "Pay once. Yours for good.")
        }
    }

    private func planTitle(_ plan: PaywallPlan) -> String {
        switch plan {
        case .yearly: String(localized: "Yearly")
        case .lifetime: String(localized: "Lifetime")
        }
    }

    private func planAccessibilityLabel(_ plan: PaywallPlan, package: SubscriptionPackage?) -> String {
        var parts = [planTitle(plan)]
        if let package {
            parts.append(package.priceString)
            parts.append(package.periodString)
            if let badge = package.introBadge {
                parts.append(badge)
            }
        }
        return parts.joined(separator: ", ")
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
                ZStack {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(KeptColor.adaptiveOnInk)
                    } else {
                        Text(ctaLabel)
                            .font(.keptHeadline)
                            .foregroundStyle(KeptColor.adaptiveOnInk)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Capsule().fill(KeptColor.adaptiveInk))
            }
            .buttonStyle(.plain)
            .disabled(isWorking || currentPackage == nil)

            if activeSelection == .yearly, let price = currentPackage?.priceString {
                Text(PaywallCatalog.yearlyRenewalLine(price: price))
                    .font(.keptFootnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 20) {
                Button("Restore Purchases") { Task { await restore() } }
                Button("Terms") {
                    open(URL(string: "https://getkept.xyz/terms"))
                }
                Button("Privacy") {
                    open(URL(string: "https://getkept.xyz/privacy"))
                }
            }
            .font(.keptFootnote)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
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
        guard let plan = activeSelection, currentPackage != nil else {
            return String(localized: "Continue")
        }
        return PaywallCatalog.buttonTitle(plan: plan, hasIntroTrial: trialAvailable)
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Helpers

    /// Yearly stays selected when it exists. A stale yearly choice falls back
    /// to lifetime when yearly is missing, and the other way around.
    private var activeSelection: PaywallPlan? {
        PaywallCatalog.resolvedSelection(selection, in: subscription.offering)
    }

    private var currentPackage: SubscriptionPackage? {
        guard let plan = activeSelection else { return nil }
        return PaywallCatalog.package(plan, in: subscription.offering)
    }

    /// True only when the selected package carries a store free-trial period.
    private var trialAvailable: Bool {
        PaywallCatalog.hasIntroTrial(currentPackage)
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
            restoreShouldDismiss = restored
            restoreNotice = restored
                ? String(localized: "Kept Pro is restored on this Apple ID.")
                : String(localized: "Nothing to restore on this Apple ID.")
            if restored { successTick &+= 1 }
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
    private(set) var offeringLoadFailed: Bool = false
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
        self.offeringLoadFailed = service.offeringLoadFailed
        self.billingIssue = service.billingIssue
        self.proAccessExpiry = service.proAccessExpiry
        self.appUserID = service.appUserID
        service.onChange = { [weak self] in
            guard let self else { return }
            self.isPro = self.service.isPro
            self.offering = self.service.offering
            self.offeringLoadFailed = self.service.offeringLoadFailed
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

private struct PlaceholderRedaction: ViewModifier {
    var isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.redacted(reason: .placeholder)
        } else {
            content
        }
    }
}

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

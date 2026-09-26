import PassKit
import SwiftData
import SwiftUI

/// When the one-time first-save sheet may appear, and the flag it stamps.
/// Pure helpers do not read UserDefaults or insert a purchase.
enum FirstSavePayoff {
    static let shownKey = "kept.hasShownFirstSavePayoff"

    /// Active warranty only. A return window, or a warranty that has already
    /// ended, does not qualify and does not stamp the flag.
    static func isEligible(warrantyExpiry: Date?, hasShown: Bool, now: Date = .now) -> Bool {
        guard !hasShown, let warrantyExpiry else { return false }
        return warrantyExpiry > now
    }

    /// Front-door paywall still runs on the 0 → 1 save when the sheet is skipped.
    static func shouldRequestPaywallWithoutSheet(
        previousCount: Int,
        newCount: Int,
        willShowSheet: Bool
    ) -> Bool {
        !willShowSheet && previousCount == 0 && newCount == 1
    }

    /// Existing libraries never get a "first save" sheet.
    static func shouldStampExistingLibrary(hasShown: Bool, purchaseCount: Int) -> Bool {
        !hasShown && purchaseCount > 0
    }

    /// Ending soon uses the user's largest warranty lead time (default 14).
    static func phase(daysRemaining: Int, leadDays: Set<Int>) -> CoverageCard.Phase {
        if daysRemaining < 0 { return .expired }
        let window = leadDays.max() ?? 14
        return daysRemaining <= window ? .endingSoon : .covered
    }

    static func daysLeft(
        until expiry: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        max(0, CoverageCardMapping.daysRemaining(until: expiry, now: now, calendar: calendar))
    }

    static var walletAvailable: Bool {
        PKPassLibrary.isPassLibraryAvailable()
            && PKAddPassesViewController.canAddPasses()
            && PassSigningService.makeDefault() != nil
    }
}

/// One-time sheet after the first save that still has an active warranty.
/// Claim pack stays Pro-gated inside `ClaimPackButton`. This view does not
/// insert or count a purchase. The flag is stamped when the sheet appears.
struct FirstSavePayoffSheet: View {
    let purchase: Purchase

    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionAccess.self) private var subscription
    @AppStorage(FirstSavePayoff.shownKey) private var hasShown = false
    @AppStorage("kept.textSize") private var textSizeRaw: String = KeptTextSize.system.rawValue

    private var userTextSize: KeptTextSize {
        KeptTextSize(rawValue: textSizeRaw) ?? .system
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(OnboardingCopy.firstSaveHeadline)
                            .font(.keptTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text(OnboardingCopy.firstSaveSubtitle)
                            .font(.keptBody)
                            .foregroundStyle(.secondary)
                    }

                    CoverageCard(
                        state: phase,
                        merchant: purchase.displayMerchant,
                        item: purchase.displayItem,
                        daysRemaining: daysLeft,
                        remainingStyle: .adaptive,
                        proof: .init(
                            receiptImage: purchase.receiptImage,
                            showsClaimPackReady: subscription.isPro
                        )
                    )

                    if FirstSavePayoff.walletAvailable {
                        VStack(spacing: Spacing.sm) {
                            AddToWalletButton(purchase: purchase, suppressesFollowUpPaywall: true)
                            Text(OnboardingCopy.walletCaption)
                                .font(.keptFootnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: Spacing.sm) {
                        ClaimPackButton(purchase: purchase)
                            .font(KeptFont.sans(17, weight: .medium, relativeTo: .body))
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .tint(.primary)
                        Text(subscription.isPro ? OnboardingCopy.claimPackCaptionPro : OnboardingCopy.claimPackCaptionFree)
                            .font(.keptFootnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .keptTextSize(userTextSize)
        .onAppear { hasShown = true }
    }

    private var warrantyExpiry: Date? {
        purchase.primaryWarranty?.expiryDate
    }

    private var daysLeft: Int {
        guard let warrantyExpiry else { return 0 }
        return FirstSavePayoff.daysLeft(until: warrantyExpiry)
    }

    private var phase: CoverageCard.Phase {
        FirstSavePayoff.phase(daysRemaining: daysLeft, leadDays: SettingsSnapshot.leadDaysSet)
    }
}

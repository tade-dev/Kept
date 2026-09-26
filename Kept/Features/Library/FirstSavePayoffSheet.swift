import SwiftData
import SwiftUI

/// One-time sheet after the library goes from 0 saved purchases to 1.
/// Shows the real coverage card for that purchase, plus the existing
/// Wallet and claim-pack actions. Claim pack stays Pro-gated inside
/// `ClaimPackButton`. This view does not insert or count a purchase.
struct FirstSavePayoffSheet: View {
    let purchase: Purchase

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Locked headline. Layout below is DESIGN-PENDING.
                    Text(OnboardingCopy.firstSaveHeadline)
                        .font(.keptTitle2)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Proof row uses the saved receipt image. "Claim pack ready" is the
                    // same card copy as the sample; ClaimPackButton below still
                    // locks the export for free users.
                    CoverageCard(
                        state: coveragePhase,
                        merchant: purchase.displayMerchant,
                        item: purchase.displayItem,
                        daysRemaining: coverageDays,
                        emphasized: true,
                        proof: CoverageProof(imageData: purchase.receiptImage)
                    )

                    // DESIGN-PENDING: first-save sheet arrangement of these existing actions.
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        AddToWalletButton(purchase: purchase)

                        ClaimPackButton(purchase: purchase)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Prefer the warranty end, then any coverage date on the saved purchase.
    private var coverageEnd: Date? {
        purchase.primaryWarranty?.expiryDate
            ?? purchase.coverageEndsAt
            ?? purchase.nextDeadline?.expiryDate
    }

    private var coveragePhase: CoverageCard.Phase {
        guard let coverageEnd else { return .covered }
        return CoverageCardMapping.phase(
            daysRemaining: CoverageCardMapping.daysRemaining(until: coverageEnd)
        )
    }

    private var coverageDays: Int {
        guard let coverageEnd else { return 0 }
        return max(0, CoverageCardMapping.daysRemaining(until: coverageEnd))
    }
}

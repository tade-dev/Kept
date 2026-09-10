import SwiftUI
import StoreKit

/// Soft nudge shown at the top of the Library while a Pro subscription is in
/// Apple's grace period after a payment failure. Not an alert — a warm amber
/// card that says "there's something to fix, tap here." Uses iOS's native
/// `.manageSubscriptionsSheet` so users update their card in an in-app sheet
/// instead of leaving to Settings.
///
/// The card is deliberately not dismissible: the entitlement WILL lapse if
/// the user ignores it, so we keep it visible until the underlying
/// `BillingIssue` clears.
struct BillingIssueBanner: View {
    let issue: BillingIssue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isManageSheetPresented = false
    @State private var haptic: Int = 0

    var body: some View {
        Button {
            haptic &+= 1
            isManageSheetPresented = true
        } label: {
            HStack(spacing: 14) {
                emblem

                VStack(alignment: .leading, spacing: 3) {
                    Text("Payment couldn't be processed")
                        .font(KeptFont.sans(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    subtitle
                        .font(.keptCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(cardBackground)
            .overlay(cardBorder)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .transition(reduceMotion
                    ? .opacity
                    : .push(from: .top).combined(with: .opacity))
        .sensoryFeedback(.impact(weight: .light), trigger: haptic)
        .manageSubscriptionsSheet(isPresented: $isManageSheetPresented)
        .accessibilityLabel(Text("Payment couldn't be processed"))
        .accessibilityHint(Text("Opens the App Store subscription manager so you can update your payment method."))
    }

    // MARK: - Emblem

    private var emblem: some View {
        ZStack {
            Circle()
                .fill(KeptColor.endingSoon.opacity(0.18))
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KeptColor.endingSoon)
        }
        .frame(width: 36, height: 36)
    }

    // MARK: - Subtitle

    /// Two shapes: with-a-date and without. When RC surfaced a grace-period
    /// end date we show a native relative countdown (`Text(_:style:)`), which
    /// SwiftUI re-renders as the current time drifts. Otherwise a static
    /// nudge.
    @ViewBuilder
    private var subtitle: some View {
        if let ends = issue.gracePeriodEndsAt {
            Text("Kept Pro pauses \(Text(ends, style: .relative)) — update your card to keep it")
        } else {
            Text("Update your card to keep Kept Pro active")
        }
    }

    // MARK: - Card chrome

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(KeptColor.endingSoon.opacity(0.08))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(KeptColor.endingSoon.opacity(0.35), lineWidth: 0.5)
    }
}

#Preview("With grace end date") {
    BillingIssueBanner(
        issue: BillingIssue(
            detectedAt: .now.addingTimeInterval(-86_400),
            gracePeriodEndsAt: .now.addingTimeInterval(4 * 86_400)
        )
    )
    .padding(.vertical)
    .background(Color(.systemGroupedBackground))
}

#Preview("Without grace end date") {
    BillingIssueBanner(
        issue: BillingIssue(detectedAt: .now, gracePeriodEndsAt: nil)
    )
    .padding(.vertical)
    .background(Color(.systemGroupedBackground))
}

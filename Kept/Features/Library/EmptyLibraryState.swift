import SwiftUI

/// Empty library. The card is a labelled sample, never a `Purchase`.
struct EmptyLibraryState: View {
    var onScan: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ViewThatFits(in: .vertical) {
                layout
                    .frame(minHeight: proxy.size.height)
                ScrollView {
                    layout
                        .frame(minWidth: proxy.size.width)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var layout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: Spacing.sm + Spacing.xs) {
                CoverageCard(
                    state: SampleCoverageCard.phase,
                    merchant: SampleCoverageCard.merchant,
                    item: SampleCoverageCard.item,
                    daysRemaining: SampleCoverageCard.daysRemaining,
                    remainingStyle: .adaptive,
                    proof: .init(receiptImage: nil, showsClaimPackReady: false),
                    isSample: true
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .onTapGesture(perform: onScan)

                Text(OnboardingCopy.emptyLibraryCaption)
                    .font(.keptFootnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)

            Text(OnboardingCopy.emptyLibraryTitle)
                .font(.keptTitle2)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, Spacing.md)

            Button(action: onScan) {
                Label("Scan a receipt", systemImage: "doc.viewfinder")
                    .font(KeptFont.sans(17, weight: .semibold, relativeTo: .body))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(KeptColor.ink)
            .controlSize(.large)
            .clipShape(Capsule())

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Light") {
    EmptyLibraryState(onScan: {})
}

#Preview("Dark") {
    EmptyLibraryState(onScan: {})
        .preferredColorScheme(.dark)
}

#Preview("Accessibility") {
    EmptyLibraryState(onScan: {})
        .environment(\.dynamicTypeSize, .accessibility5)
}

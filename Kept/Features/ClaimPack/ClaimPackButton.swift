import SwiftUI

/// Export button that walks the user through:
/// tap → HUD loader → PDF preview sheet → in-sheet Export → iOS share sheet.
///
/// Free users see a lock and get the paywall instead.
struct ClaimPackButton: View {
    let purchase: Purchase

    @Environment(SubscriptionAccess.self) private var subscription
    @State private var isPresentingPaywall = false
    @State private var isRendering = false
    @State private var preview: PreviewItem?

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack {
                Label("Export claim pack", systemImage: "doc.badge.arrow.up")
                Spacer()
                if !subscription.isPro {
                    Image(systemName: "lock.fill")
                        .font(KeptFont.sans(12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isRendering)
        .sheet(isPresented: $isPresentingPaywall) {
            PaywallView(reason: .claimPack)
                .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $isRendering) {
            ClaimPackLoadingHUD()
                .presentationBackground(.clear)
        }
        .sheet(item: $preview) { item in
            ClaimPackPreviewSheet(url: item.url, filename: item.filename)
        }
    }

    private func handleTap() {
        guard subscription.isPro else {
            isPresentingPaywall = true
            return
        }
        isRendering = true
        Task { @MainActor in
            let start = Date.now
            let url = try? ClaimPackRenderer.renderToTempFile(purchase: purchase)
            // Minimum HUD duration so the loader feels intentional, not a flash.
            let elapsed = Date.now.timeIntervalSince(start)
            let minDuration: TimeInterval = 0.45
            if elapsed < minDuration {
                try? await Task.sleep(for: .seconds(minDuration - elapsed))
            }
            isRendering = false
            // Let fullScreenCover finish dismissing before the sheet slides up.
            try? await Task.sleep(for: .milliseconds(180))
            if let url {
                preview = PreviewItem(
                    url: url,
                    filename: ClaimPackRenderer.filename(for: purchase, at: .now)
                )
                maybeRequestReview()
            }
        }
    }

    /// Claim pack export is the moment Kept's whole product exists for
    /// — the "day it mattered." Best positive moment to ask for a
    /// review. Fires only once per install; iOS handles further
    /// throttling. Delayed so the preview sheet finishes presenting
    /// before the review alert appears.
    @AppStorage("kept.hasRequestedReviewAfterClaimPack") private var hasRequestedReviewAfterClaimPack = false

    private func maybeRequestReview() {
        guard !hasRequestedReviewAfterClaimPack else { return }
        hasRequestedReviewAfterClaimPack = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            ReviewPrompter.request()
        }
    }
}

// MARK: - Loader HUD

private struct ClaimPackLoadingHUD: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.primary)
                Text("Preparing your claim pack")
                    .font(KeptFont.sans(14, weight: .medium, relativeTo: .footnote))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        }
    }
}

// MARK: - Sheet item

private struct PreviewItem: Identifiable {
    let url: URL
    let filename: String
    var id: URL { url }
}

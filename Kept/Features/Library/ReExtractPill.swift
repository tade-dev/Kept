import SwiftUI

/// Floating pill CTA that lets the user reprocess a receipt through the
/// latest extractor when the original scan came back thin. Anchored via
/// `safeAreaInset(edge: .bottom)` so it hovers above the form scroll.
///
/// Owns no state of its own — the parent controls appearance timing (for
/// the springs-in transition) and the working spinner.
struct ReExtractPill: View {
    var isWorking: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(KeptFont.sans(15, weight: .semibold, relativeTo: .body))
                }
                Text(isWorking ? "Re-extracting…" : "Re-extract with latest AI")
                    .font(KeptFont.sans(15, weight: .semibold, relativeTo: .body))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        ReExtractPill(isWorking: false) {}
            .padding(.bottom, 24)
    }
}

import SwiftUI

/// A single-tap celebration sheet that pops after Kept's server has granted
/// the user 7 days of Kept Pro because they hit the engagement threshold in
/// the first 24 hours. Deliberately understated — a card, a warm line of
/// copy, and a "Continue" button. No confetti, no marketing.
///
/// The parent presents this via `.sheet(isPresented:)` — sheet dismissal
/// (button tap or drag) hands control cleanly back to the library.
struct TrialBoostCelebration: View {
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            emblem
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.55, dampingFraction: 0.72), value: appeared)

            VStack(spacing: 10) {
                Text("7 days of Kept Pro")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)

                Text("You've saved a few receipts already — here's a week of Kept Pro on us to see what the upgrade unlocks.")
                    .font(.keptSubheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(.snappy(duration: 0.42).delay(0.12), value: appeared)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.keptHeadline)
                    .foregroundStyle(KeptColor.adaptiveOnInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(KeptColor.adaptiveInk))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .opacity(appeared ? 1 : 0)
            .animation(.snappy(duration: 0.32).delay(0.22), value: appeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear { appeared = true }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var emblem: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.22),
                            Color.accentColor.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 128, height: 128)

            Image(systemName: "gift.fill")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, options: .nonRepeating)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TrialBoostCelebration()
        }
}

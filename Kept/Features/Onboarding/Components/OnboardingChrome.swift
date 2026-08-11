import SwiftUI

/// Circular back chevron + thin progress bar, side-by-side, pinned to the top.
struct OnboardingChrome: View {
    let fraction: Double
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.md) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color(.secondarySystemBackground))
                    )
            }
            .accessibilityLabel("Back")

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(KeptColor.ink)
                        .frame(width: max(0, proxy.size.width * fraction))
                        .animation(
                            reduceMotion ? .none : .snappy(duration: 0.32),
                            value: fraction
                        )
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, Spacing.lg)
    }
}

#Preview {
    VStack(spacing: 40) {
        OnboardingChrome(fraction: 0.2, onBack: {})
        OnboardingChrome(fraction: 0.6, onBack: {})
        OnboardingChrome(fraction: 1.0, onBack: {})
        Spacer()
    }
}

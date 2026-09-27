import SwiftUI

/// Pause-and-think beat. Presented right after Welcome and before the
/// key-moment demo so the user answers "when would this matter to me?"
/// mentally before we show Kept in action.
///
/// Kept deliberately airy — this beat's job is to make the user *stop*,
/// not to load them up. One symbol, one line, one line. A soft haptic
/// on arrival signals the moment.
struct WhyNowStepView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrivedTick = 0

    var body: some View {
        OnboardingScaffold(
            title: OnboardingCopy.whyNowHeadline,
            subtitle: OnboardingCopy.whyNowSubhead
        ) {
            VStack {
                Spacer()
                clockGlyph
                Spacer()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: arrivedTick)
        .task { arrivedTick &+= 1 }
    }

    /// A quiet clock with a subtle live second-hand tick — the countdown
    /// is Kept's central metaphor, so the visual echoes it without
    /// spelling it out. Reduce Motion pins the hand at 12.
    private var clockGlyph: some View {
        Image(systemName: "clock")
            .font(KeptFont.sans(64, weight: .regular, relativeTo: .largeTitle))
            .foregroundStyle(.primary)
            .symbolEffect(
                .pulse,
                options: reduceMotion ? .nonRepeating : .repeat(.periodic(delay: 2.2))
            )
            .padding(28)
            .background(
                Circle()
                    .fill(Color(.secondarySystemBackground))
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    WhyNowStepView()
}

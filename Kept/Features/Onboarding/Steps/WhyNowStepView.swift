import SwiftUI

/// Pause-and-think beat. Presented right after Welcome and before the
/// key-moment demo so the user answers "when would this matter to me?"
/// mentally before we show Kept in action.
///
/// Editorial layout — the copy is the visual. No glyph, no illustration:
/// a decorated pause dilutes what the words are trying to do. Headline
/// and subhead are stacked at the vertical centre with generous
/// whitespace above and below, giving the beat room to land.
struct WhyNowStepView: View {
    @State private var arrivedTick = 0

    var body: some View {
        // Passing an empty scaffold title with `stylesTitle: false` keeps
        // the shared step layout (padding, safe areas) while letting this
        // step centre the copy in the content area — no top-anchored
        // header competing for attention.
        OnboardingScaffold(
            titleText: Text(""),
            stylesTitle: false
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Spacer(minLength: 0)

                Text(OnboardingCopy.whyNowHeadline)
                    .font(KeptFont.sans(36, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(OnboardingCopy.whyNowSubhead)
                    .font(KeptFont.sans(20, weight: .regular, relativeTo: .title3))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.lg)
        }
        // Light haptic — the beat is quiet, so the feedback is too.
        .sensoryFeedback(.impact(weight: .light), trigger: arrivedTick)
        .task { arrivedTick &+= 1 }
    }
}

#Preview {
    WhyNowStepView()
}

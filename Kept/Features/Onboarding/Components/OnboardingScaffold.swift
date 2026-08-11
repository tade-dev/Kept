import SwiftUI

/// Step body layout: big title + optional subtitle + content + optional footer.
/// No chrome, no CTA — those live in OnboardingView and stay fixed across step transitions.
struct OnboardingScaffold<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleSection
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

            content()
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer()
                .padding(.horizontal, Spacing.lg)
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

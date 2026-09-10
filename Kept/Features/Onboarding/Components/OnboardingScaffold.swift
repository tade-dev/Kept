import SwiftUI

/// Step body layout: big title + optional subtitle + content + optional footer.
/// No chrome, no CTA — those live in OnboardingView and stay fixed across step transitions.
///
/// Title and subtitle are stored as `Text` so callers can pass either a
/// literal (`Text("What do you...")` — resolved via the string catalog) or
/// a pre-localised dynamic string (`Text(verbatim: someString)` — displayed
/// as-is). This keeps the component from having to know whether the value
/// is a catalog key or an already-resolved string.
struct OnboardingScaffold<Content: View, Footer: View>: View {
    let title: Text
    var subtitle: Text? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    /// Preferred init — pass a `LocalizedStringKey` literal for the title +
    /// optional subtitle and the string catalog handles the rest.
    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
        self.content = content
        self.footer = footer
    }

    /// Escape hatch for callers whose title is a runtime-built string that
    /// has already been localised (e.g. plural formatting done via
    /// `String(localized:)`). Pass a `Text(verbatim:)` when the value
    /// mustn't be re-looked-up against the catalog.
    init(
        titleText: Text,
        subtitleText: Text? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.title = titleText
        self.subtitle = subtitleText
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
            title
                .font(KeptFont.sans(36, weight: .bold, relativeTo: .largeTitle))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                subtitle
                    .font(.keptTitle3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

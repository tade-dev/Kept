import SwiftUI

/// Central font tokens for Kept. Everything goes through **Bricolage Grotesque**.
///
/// Adopt in views via `.font(.keptBody)` / `.font(.keptHeadline)` etc.
/// All styles use `Font.custom(..., relativeTo:)` so Dynamic Type scaling still
/// works. If a `.ttf` isn't in the bundle, SwiftUI silently falls back to the
/// system font.
///
/// PostScript names include `24pt` because Google Fonts ships Bricolage
/// Grotesque as an optical-size family; the bundled `static/*24pt*.ttf` files
/// are the 24pt optical instances.
enum KeptFont {
    private enum Sans {
        static let regular  = "BricolageGrotesque24pt-Regular"
        static let medium   = "BricolageGrotesque24pt-Medium"
        static let semibold = "BricolageGrotesque24pt-SemiBold"
        static let bold     = "BricolageGrotesque24pt-Bold"
    }

    // MARK: - Text-style tokens (Dynamic Type-aware)

    static var largeTitle:  Font { .custom(Sans.bold,     size: 34, relativeTo: .largeTitle) }
    static var title:       Font { .custom(Sans.bold,     size: 28, relativeTo: .title) }
    static var title2:      Font { .custom(Sans.semibold, size: 22, relativeTo: .title2) }
    static var title3:      Font { .custom(Sans.semibold, size: 20, relativeTo: .title3) }
    static var headline:    Font { .custom(Sans.semibold, size: 17, relativeTo: .headline) }
    static var body:        Font { .custom(Sans.regular,  size: 17, relativeTo: .body) }
    static var callout:     Font { .custom(Sans.regular,  size: 16, relativeTo: .callout) }
    static var subheadline: Font { .custom(Sans.regular,  size: 15, relativeTo: .subheadline) }
    static var footnote:    Font { .custom(Sans.regular,  size: 13, relativeTo: .footnote) }
    static var caption:     Font { .custom(Sans.regular,  size: 12, relativeTo: .caption) }
    static var caption2:    Font { .custom(Sans.regular,  size: 11, relativeTo: .caption2) }

    /// Custom pixel-sized cuts for hero moments (paywall price, welcome headline, etc.)
    static func sans(_ size: CGFloat, weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(sansName(for: weight), size: size, relativeTo: style)
    }

    enum Weight { case regular, medium, semibold, bold }

    private static func sansName(for weight: Weight) -> String {
        switch weight {
        case .regular:  Sans.regular
        case .medium:   Sans.medium
        case .semibold: Sans.semibold
        case .bold:     Sans.bold
        }
    }
}

// MARK: - Convenience aliases so `.font(.keptBody)` reads like a system style

extension Font {
    static var keptLargeTitle:  Font { KeptFont.largeTitle }
    static var keptTitle:       Font { KeptFont.title }
    static var keptTitle2:      Font { KeptFont.title2 }
    static var keptTitle3:      Font { KeptFont.title3 }
    static var keptHeadline:    Font { KeptFont.headline }
    static var keptBody:        Font { KeptFont.body }
    static var keptCallout:     Font { KeptFont.callout }
    static var keptSubheadline: Font { KeptFont.subheadline }
    static var keptFootnote:    Font { KeptFont.footnote }
    static var keptCaption:     Font { KeptFont.caption }
    static var keptCaption2:    Font { KeptFont.caption2 }
}

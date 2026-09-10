import SwiftUI

/// Canonical color tokens. One accent (`ink`) + three coverage states.
/// State colors carry meaning — do not use them decoratively.
enum KeptColor {
    /// Primary accent: buttons, active chrome, brand ink.
    static let ink = Color(red: 0.055, green: 0.090, blue: 0.165)

    /// "Everything's fine, plenty of time left." Cool, calm.
    static let covered = Color(red: 0.392, green: 0.455, blue: 0.545)

    /// Inside the lead window. Warm without being alarming.
    static let endingSoon = Color(red: 0.961, green: 0.620, blue: 0.043)

    /// Past expiry. Muted grey — done, not urgent.
    static let expired = Color(red: 0.580, green: 0.639, blue: 0.722)

    /// Foreground that reads on `ink` fills.
    static let onInk = Color.white

    /// Ink-toned fill that flips in dark mode. Use for primary buttons and
    /// chrome that should keep an "ink slab" identity in both appearances —
    /// deep navy on light, warm paper on dark. Pair with `adaptiveOnInk` for
    /// legible text on top.
    static let adaptiveInk = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.960, green: 0.960, blue: 0.933, alpha: 1.0)
            : UIColor(red: 0.055, green: 0.090, blue: 0.165, alpha: 1.0)
    })

    /// Foreground counterpart to `adaptiveInk`. Renders as paper-white in
    /// light mode (on ink) and as ink in dark mode (on paper).
    static let adaptiveOnInk = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.090, blue: 0.165, alpha: 1.0)
            : UIColor.white
    })
}

/// Spacing scale. Prefer these to raw pixel constants.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

/// Corner radii shared across chrome so cards, sheets, and buttons feel one family.
enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
}

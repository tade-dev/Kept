import SwiftUI

/// Kept's display serif — Instrument Serif. Used on countdown numerals and
/// item names for warmth; everything else stays SF Pro per HIG.
enum KeptFont {
    private static let serifRegular = "InstrumentSerif-Regular"
    private static let serifItalic = "InstrumentSerif-Italic"

    /// Scales with Dynamic Type via a matching text style.
    static func serif(_ size: CGFloat, italic: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom(italic ? serifItalic : serifRegular, size: size, relativeTo: style)
    }
}

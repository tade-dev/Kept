import SwiftUI

/// iOS Settings-style row: a coloured rounded-rect icon tile on the
/// left, the label in the middle, an optional detail value on the
/// right, and a chevron to signal the row opens a sheet.
///
/// The colour is passed in so different rows can subtly differentiate
/// (all Kept accessibility rows share the same blue tint by design).
struct AccessibilityTile: View {
    let icon: String
    let tint: Color
    /// Row title. Pass a literal — treated as a catalog key so it localises.
    let label: LocalizedStringKey
    /// Trailing value on the row. This is usually a dynamic string sourced
    /// from a state enum ("Large" / "System" / "Off"), so callers pre-
    /// localise it via `String(localized:)` and we render verbatim.
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconTile
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if let detail {
                    Text(verbatim: detail)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: detail ?? ""))
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tint)
            .frame(width: 29, height: 29)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    // Subtle life on the tiny tile — bounce once when
                    // the section first appears. Not distracting, but
                    // signals "this is an active row, not just chrome."
                    .symbolEffect(.bounce, options: .nonRepeating)
            )
    }
}

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
    let label: String
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
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(detail ?? "")
        .accessibilityHint("Opens Kept's \(label.lowercased()) settings.")
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

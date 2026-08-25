import SwiftUI

/// Wraps any `Label`'s icon in an iOS Settings-style rounded-tile
/// so `ShareLink`, `Button`, and `Link` rows sit visually alongside
/// the `AccessibilityTile` rows without any structural refactor.
struct SettingsTileLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            configuration.title
        }
    }
}

extension LabelStyle where Self == SettingsTileLabelStyle {
    static func settingsTile(tint: Color) -> SettingsTileLabelStyle {
        SettingsTileLabelStyle(tint: tint)
    }
}

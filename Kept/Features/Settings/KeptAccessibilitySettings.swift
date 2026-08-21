import SwiftUI

/// User-selectable text-size override for Kept only. When set to
/// `.system`, Kept follows iOS's system-wide Dynamic Type setting;
/// otherwise this value wins for every text token in the app via
/// `.dynamicTypeSize(_:)` applied at the root.
///
/// Deliberately does NOT expose AX1–AX5 as in-app options. Those sizes
/// stress every layout and users who need them are best served by the
/// system-wide setting (which applies here too via `.system`).
enum KeptTextSize: String, CaseIterable, Identifiable, Sendable {
    case system
    case small
    case medium
    case large
    case xLarge
    case xxLarge
    case xxxLarge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:   "Follow iOS"
        case .small:    "Small"
        case .medium:   "Medium"
        case .large:    "Large"
        case .xLarge:   "Extra Large"
        case .xxLarge:  "XXL"
        case .xxxLarge: "XXXL"
        }
    }

    /// The `DynamicTypeSize` to force on the view hierarchy. Returns
    /// `nil` for `.system`, meaning "don't override — let the
    /// environment pass through."
    var override: DynamicTypeSize? {
        switch self {
        case .system:   nil
        case .small:    .small
        case .medium:   .medium
        case .large:    .large
        case .xLarge:   .xLarge
        case .xxLarge:  .xxLarge
        case .xxxLarge: .xxxLarge
        }
    }
}

/// In-app override for reducing motion, independent of iOS's system
/// Reduce Motion. When `.system`, follows iOS; when `.always`, treats
/// reduce-motion as on regardless of iOS. No "always off" option —
/// respecting the OS setting is the ethical floor.
enum KeptMotionPreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case always

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "Follow iOS"
        case .always: "Always reduce"
        }
    }
}

// MARK: - View helper

extension View {
    /// Applies Kept's in-app text-size override when the user has picked
    /// one; otherwise leaves the environment's Dynamic Type value alone
    /// so system settings still take effect.
    func keptTextSize(_ preference: KeptTextSize) -> some View {
        Group {
            if let size = preference.override {
                self.dynamicTypeSize(size)
            } else {
                self
            }
        }
    }
}

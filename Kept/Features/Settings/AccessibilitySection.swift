import SwiftUI

/// In-app accessibility controls surfaced as iOS Settings-style tiles.
/// Each tile owns its own sheet presentation via a local `@State`
/// boolean — `.sheet(item:)` on a Section inside a Form auto-dismisses
/// on the first re-render (a SwiftUI quirk), so per-tile isPresented
/// is the reliable path.
struct AccessibilitySection: View {
    @AppStorage("kept.textSize") private var textSizeRaw: String = KeptTextSize.system.rawValue
    @AppStorage("kept.motion")   private var motionRaw:   String = KeptMotionPreference.system.rawValue
    @AppStorage(SettingsKeys.darkAccent) private var darkAccentRaw: String = DarkAccentPreference.midnight.rawValue

    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var accentTint: Color {
        (DarkAccentPreference(rawValue: darkAccentRaw) ?? .midnight).tint
    }

    private var textSizeBinding: Binding<KeptTextSize> {
        Binding(
            get: { KeptTextSize(rawValue: textSizeRaw) ?? .system },
            set: { textSizeRaw = $0.rawValue }
        )
    }

    private var motionBinding: Binding<KeptMotionPreference> {
        Binding(
            get: { KeptMotionPreference(rawValue: motionRaw) ?? .system },
            set: { motionRaw = $0.rawValue }
        )
    }

    private var textSize: KeptTextSize { textSizeBinding.wrappedValue }
    private var motion: KeptMotionPreference { motionBinding.wrappedValue }

    var body: some View {
        Section {
            TextSizeRow(
                tint: accentTint,
                textSize: textSizeBinding
            )
            MotionRow(
                tint: accentTint,
                motion: motionBinding
            )
            VoiceOverRow(
                tint: accentTint,
                enabled: voiceOverEnabled
            )
            ContrastRow(
                tint: accentTint,
                enabled: colorSchemeContrast == .increased
            )
        } header: {
            Text("Accessibility")
        } footer: {
            Text("Text size and motion apply to Kept. VoiceOver and Contrast are system-wide iOS settings, Kept respects whatever you've set there.")
        }
    }
}

// MARK: - Per-tile rows, each owning its own sheet state

private struct TextSizeRow: View {
    let tint: Color
    @Binding var textSize: KeptTextSize
    @State private var isPresented = false

    var body: some View {
        AccessibilityTile(
            icon: "textformat.size",
            tint: tint,
            label: "Text size",
            detail: textSize == .system
                ? String(localized: "System")
                : String(localized: LocalizedStringResource(stringLiteral: textSize.displayName))
        ) {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            TextSizeSheet(textSize: $textSize)
                .presentationDetents([.large])
        }
    }
}

private struct MotionRow: View {
    let tint: Color
    @Binding var motion: KeptMotionPreference
    @State private var isPresented = false

    var body: some View {
        AccessibilityTile(
            icon: "figure.walk.motion",
            tint: tint,
            label: "Motion",
            detail: motion == .system
                ? String(localized: "System")
                : String(localized: "Reduced")
        ) {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            ReduceMotionSheet(preference: $motion)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct VoiceOverRow: View {
    let tint: Color
    let enabled: Bool
    @State private var isPresented = false

    var body: some View {
        AccessibilityTile(
            icon: "speaker.wave.2.circle.fill",
            tint: tint,
            label: "VoiceOver",
            detail: enabled ? String(localized: "On") : String(localized: "Off")
        ) {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            AccessibilityStatusSheet(
                icon: "speaker.wave.2.circle.fill",
                title: "VoiceOver",
                currentStatus: enabled ? "on" : "off",
                systemExplanation: "Turn VoiceOver on or off in iOS Settings → Accessibility → VoiceOver, or triple-click the side button if you've set it as an accessibility shortcut.",
                inKeptExplanation: "Every receipt in Kept has a full spoken description — item, merchant, purchase date, coverage remaining. Swipe actions and coach marks are reachable via the Actions rotor.",
                settingsURL: URL(string: "App-Prefs:root=ACCESSIBILITY&path=VOICEOVER_TITLE")
            )
            .presentationDetents([.medium, .large])
        }
    }
}

private struct ContrastRow: View {
    let tint: Color
    let enabled: Bool
    @State private var isPresented = false

    var body: some View {
        AccessibilityTile(
            icon: "circle.righthalf.filled",
            tint: tint,
            label: "Increase Contrast",
            detail: enabled ? String(localized: "On") : String(localized: "Off")
        ) {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            AccessibilityStatusSheet(
                icon: "circle.righthalf.filled",
                title: "Increase Contrast",
                currentStatus: enabled ? "on" : "off",
                systemExplanation: "Turn Increase Contrast on or off in iOS Settings → Accessibility → Display & Text Size → Increase Contrast.",
                inKeptExplanation: "Kept bumps up divider weights, borders, and secondary text when this is on so the ink-on-paper aesthetic stays legible without straining.",
                settingsURL: URL(string: "App-Prefs:root=ACCESSIBILITY&path=DISPLAY")
            )
            .presentationDetents([.medium, .large])
        }
    }
}

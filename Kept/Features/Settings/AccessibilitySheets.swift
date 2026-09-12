import SwiftUI

// MARK: - Reduce Motion sheet

/// Kept-side motion override. Users on the fence can either respect
/// the system Reduce Motion setting or force it on for Kept specifically
/// (e.g. iOS off but they still want quieter animations in this app).
struct ReduceMotionSheet: View {
    @Binding var preference: KeptMotionPreference
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var isFollowingSystem: Bool {
        preference == .system
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                heroPanel

                VStack(spacing: 12) {
                    optionRow(
                        title: "Follow iOS",
                        subtitle: "Respect the system Reduce Motion setting.",
                        selected: preference == .system,
                        action: { preference = .system }
                    )
                    optionRow(
                        title: "Always reduce",
                        subtitle: "Quieter animations in Kept even when iOS is set to normal.",
                        selected: preference == .always,
                        action: { preference = .always }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Motion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    @State private var motionPulse = false

    private var heroPanel: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 2.4)))

            Text("Softer animations")
                .font(.keptTitle3)

            Text("Kept honours iOS Reduce Motion. You can also force it on here — springs become fades, transitions become dissolves.")
                .font(.keptFootnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func optionRow(
        title: String,
        subtitle: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color(.tertiaryLabel))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - System-status sheets (VoiceOver / Increase Contrast)

/// Informational sheet for iOS-owned settings Kept respects but can't
/// override. Shows current status + short explanation of how Kept
/// adapts to the setting.
struct AccessibilityStatusSheet: View {
    let icon: String
    let title: String
    let currentStatus: String
    let systemExplanation: String
    let inKeptExplanation: String
    /// Deep link into the relevant iOS Settings pane. Uses the
    /// undocumented `App-Prefs:` scheme — supported since iOS 10 but
    /// technically private, so we gate the CTA behind `canOpenURL` and
    /// silently hide it if a future iOS clamps down.
    var settingsURL: URL? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var canOpenSettings: Bool {
        guard let settingsURL else { return false }
        return UIApplication.shared.canOpenURL(settingsURL)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: 20) {
                    infoBlock(title: "Where to change it",
                              body: systemExplanation)
                    infoBlock(title: "How Kept adapts",
                              body: inKeptExplanation)

                    if let settingsURL, canOpenSettings {
                        Button {
                            openURL(settingsURL)
                            dismiss()
                        } label: {
                            Label("Open in Settings", systemImage: "arrow.up.forward.app")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 14))
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)

                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    @State private var iconPulse = false

    private var hero: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                // Symbols that support layered animation (waves,
                // half-filled circles, etc.) get variable-color for a
                // subtle sense-of-life. Other symbols degrade to
                // .pulse which works on every glyph.
                .symbolEffect(.variableColor.iterative.reversing, options: .repeat(.continuous))
                .symbolEffect(.pulse, options: .repeat(.periodic(delay: 3)))

            Text("Currently \(currentStatus)")
                .font(.keptTitle3)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func infoBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(body)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

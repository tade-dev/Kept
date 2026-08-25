import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw: String = AppearancePreference.system.rawValue
    @AppStorage(SettingsKeys.darkAccent) private var darkAccentRaw: String = DarkAccentPreference.midnight.rawValue

    private var selectedAppearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    private var selectedAccent: DarkAccentPreference {
        DarkAccentPreference(rawValue: darkAccentRaw) ?? .midnight
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 34) {
                appearanceOptions
                footerCopy
                accentOptions
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 36)
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .background(.background)
    }

    private var appearanceOptions: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(AppearancePreference.allCases) { preference in
                AppearanceOptionCard(
                    preference: preference,
                    accent: selectedAccent,
                    isSelected: preference == selectedAppearance
                ) {
                    setAppearance(preference)
                }
            }
        }
    }

    private var footerCopy: some View {
        Text("If System is selected, Kept follows your iPhone appearance.")
            .font(.keptCallout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
    }

    private var accentOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Accent")
                    .font(.keptHeadline)
                Text("Tune the personality of Kept.")
                    .font(.keptSubheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                ForEach(DarkAccentPreference.allCases) { accent in
                    Button {
                        setAccent(accent)
                    } label: {
                        DarkAccentRow(
                            accent: accent,
                            isSelected: accent == selectedAccent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func setAppearance(_ preference: AppearancePreference) {
        guard preference != selectedAppearance else { return }
        if reduceMotion {
            appearanceRaw = preference.rawValue
        } else {
            withAnimation(.snappy(duration: 0.32, extraBounce: 0.04)) {
                appearanceRaw = preference.rawValue
            }
        }
    }

    private func setAccent(_ accent: DarkAccentPreference) {
        guard accent != selectedAccent else { return }
        if reduceMotion {
            darkAccentRaw = accent.rawValue
        } else {
            withAnimation(.snappy(duration: 0.32, extraBounce: 0.04)) {
                darkAccentRaw = accent.rawValue
            }
        }
    }
}

private struct AppearanceOptionCard: View {
    let preference: AppearancePreference
    let accent: DarkAccentPreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ThemePreview(preference: preference, accent: accent)
                    .frame(height: 128)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)

                Text(preference.label)
                    .font(.keptHeadline)
                    .foregroundStyle(.primary)
                    .padding(.bottom, 12)

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(isSelected ? accent.tint : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(isSelected ? 1.03 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(preference.label) appearance")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
        }
        .buttonStyle(.plain)
    }
}

private struct ThemePreview: View {
    let preference: AppearancePreference
    let accent: DarkAccentPreference

    var body: some View {
        ZStack {
            previewBody(isDark: preference == .dark)

            if preference == .system {
                GeometryReader { proxy in
                    let diagonal = Path { path in
                        path.move(to: CGPoint(x: proxy.size.width, y: 0))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: proxy.size.width * 0.28, y: proxy.size.height))
                        path.closeSubpath()
                    }

                    previewBody(isDark: true)
                        .mask(diagonal)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderColor, lineWidth: 3)
        }
        .shadow(color: .black.opacity(preference == .light ? 0.08 : 0.24), radius: 18, y: 10)
    }

    private var borderColor: Color {
        switch preference {
        case .light: Color.black.opacity(0.12)
        case .dark: Color.white.opacity(0.18)
        case .system: Color.secondary.opacity(0.28)
        }
    }

    private func previewBody(isDark: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isDark ? Color(red: 0.10, green: 0.10, blue: 0.11) : Color.white)

            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDark ? accent.tint.opacity(0.45) : accent.tint.opacity(0.12))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image("KeptLockup")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(isDark ? .white.opacity(0.86) : accent.tint.opacity(0.42))
                            .padding(10)
                    }

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(lineColor(isDark: isDark))
                    .frame(width: 82, height: 12)

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tileColor(isDark: isDark))
                            .frame(height: 30)
                    }
                }
                .padding(.horizontal, 14)

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tileColor(isDark: isDark))
                    .frame(height: 42)
                    .padding(.horizontal, 14)
            }
            .padding(.vertical, 14)
        }
    }

    private func lineColor(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10)
    }

    private func tileColor(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.09)
    }
}

private struct DarkAccentRow: View {
    let accent: DarkAccentPreference
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(accent.gradient)
                .frame(width: 42, height: 42)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.55), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(accent.label)
                    .font(.keptHeadline)
                    .foregroundStyle(.primary)
                Text(accent.detail)
                    .font(.keptCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isSelected ? accent.tint : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? accent.tint.opacity(0.12) : Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? accent.tint.opacity(0.42) : Color.clear, lineWidth: 1)
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}

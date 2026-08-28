import SwiftUI

/// Picker for the app's UI language. iOS 26's SwiftUI resolves `Text` strings
/// via a path that bypasses classic `NSBundle` swizzling, so an instant swap
/// isn't reliable. Instead we persist the choice to `AppleLanguages` — the
/// standard `UserDefaults` key `NSBundle` reads at process launch — and prompt
/// the user to relaunch. This is the pattern Duolingo, Telegram, and WhatsApp
/// use for in-app language switching.
struct LanguagePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw: String = AppLanguage.system.rawValue
    @State private var pendingChoice: AppLanguage?
    @State private var haptic: Int = 0

    private var selected: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .system
    }

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    row(for: language)
                }
            } footer: {
                Text("Kept relaunches to apply your language choice.")
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .light), trigger: haptic)
        .alert(
            "Relaunch Kept?",
            isPresented: Binding(
                get: { pendingChoice != nil },
                set: { if !$0 { pendingChoice = nil } }
            ),
            presenting: pendingChoice
        ) { choice in
            Button("Relaunch", role: .destructive) {
                apply(choice)
            }
            Button("Cancel", role: .cancel) {}
        } message: { choice in
            Text("Kept will close and open again in \(choice.nativeName).")
        }
    }

    private func row(for language: AppLanguage) -> some View {
        Button {
            guard language != selected else { return }
            pendingChoice = language
        } label: {
            HStack(spacing: 12) {
                Text(language.flag)
                    .font(.system(size: 26))
                    .frame(width: 36, alignment: .center)

                Text(language.nativeName)
                    .foregroundStyle(.primary)

                Spacer()

                if language == selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.nativeName)
        .accessibilityAddTraits(language == selected ? [.isSelected] : [])
    }

    private func apply(_ language: AppLanguage) {
        languageRaw = language.rawValue
        AppLanguage.persistToAppleLanguages(language)
        haptic &+= 1
        // Give the haptic a beat, then bring the app down cleanly. iOS will
        // relaunch it on next tap in the chosen language.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            exit(0)
        }
    }
}

#Preview {
    NavigationStack {
        LanguagePickerView()
    }
}

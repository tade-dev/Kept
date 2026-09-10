import SwiftUI

/// Compact "🇬🇧 English ›" chip shown at the top-right of the welcome step.
/// Tapping opens `LanguagePickerView` as a sheet so first-run users can pick
/// their language before the onboarding copy scrolls past them.
struct LanguageBadge: View {
    @AppStorage(AppLanguage.storageKey) private var languageRaw: String = AppLanguage.system.rawValue
    @State private var isPickerPresented = false

    private var current: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .system
    }

    /// The name shown on the chip. `.system` deliberately resolves to the
    /// resolved iOS language's native name (English, Español, …) rather than
    /// the literal "Follow iOS" — the chip is a visible signal of the current
    /// display language, not a picker state.
    private var displayName: String {
        switch current {
        case .system:
            let code = Bundle.main.preferredLocalizations.first ?? "en"
            return AppLanguage(rawValue: code)?.nativeName
                ?? Locale(identifier: code).localizedString(forIdentifier: code)?.capitalized
                ?? "English"
        default:
            return current.nativeName
        }
    }

    private var displayFlag: String {
        if current == .system {
            let code = Bundle.main.preferredLocalizations.first ?? "en"
            return AppLanguage(rawValue: code)?.flag ?? "🌐"
        }
        return current.flag
    }

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 6) {
                Text(displayFlag)
                    .font(.system(size: 15))
                Text(displayName)
                    .font(KeptFont.sans(14, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Language"))
        .accessibilityValue(Text(displayName))
        .accessibilityHint(Text("Choose the app's display language."))
        .sheet(isPresented: $isPickerPresented) {
            NavigationStack {
                LanguagePickerView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isPickerPresented = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

#Preview {
    LanguageBadge()
        .padding()
}

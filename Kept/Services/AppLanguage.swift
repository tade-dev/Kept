import Foundation

/// The set of UI languages Kept ships. `.system` means "follow whatever iOS
/// is set to" via the standard `AppleLanguages` mechanism.
///
/// Storage is a plain string in `UserDefaults` so `@AppStorage` binds cleanly
/// from SwiftUI.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system  = ""
    case en
    case es
    case fr
    case zhHans  = "zh-Hans"

    static let storageKey = "kept.language"

    var id: String { rawValue }

    /// The bundle language folder to load, or `nil` for the system default.
    var bundleCode: String? {
        self == .system ? nil : rawValue
    }

    /// Displayed in the picker. Native form regardless of current UI locale —
    /// Apple convention (Spanish stays "Español" when UI is French).
    var nativeName: String {
        switch self {
        case .system: String(localized: "Follow iOS", comment: "Language picker option that defers to the system language")
        case .en:     "English"
        case .es:     "Español"
        case .fr:     "Français"
        case .zhHans: "中文"
        }
    }

    /// Compact flag emoji shown on the picker chip. `.system` uses a globe.
    var flag: String {
        switch self {
        case .system: "🌐"
        case .en:     "🇬🇧"
        case .es:     "🇪🇸"
        case .fr:     "🇫🇷"
        case .zhHans: "🇨🇳"
        }
    }
}

extension AppLanguage {
    /// Writes the choice into `AppleLanguages` — the standard iOS UserDefaults
    /// key that `NSBundle` reads at process launch to pick the strings bundle.
    /// The next cold start of Kept comes up in the chosen language.
    ///
    /// This is the canonical pattern used by apps like Duolingo, Telegram, and
    /// WhatsApp for app-controlled language: we can't hot-swap `Bundle.main`'s
    /// preferred localizations reliably on iOS 26 (SwiftUI's `Text` bypasses
    /// the classic `NSBundle.localizedString` swizzle path), so instead we
    /// persist the choice and gracefully exit — the user re-taps Kept and
    /// sees the new language.
    static func persistToAppleLanguages(_ language: AppLanguage) {
        if let code = language.bundleCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}

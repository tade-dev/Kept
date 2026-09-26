import Foundation
import SwiftUI

enum SettingsKeys {
    static let notificationsEnabled = "settings.notificationsEnabled"
    static let expiryRemindersEnabled = "settings.expiryRemindersEnabled"
    static let weeklyReminderEnabled = "settings.weeklyReminderEnabled"
    static let lastAppOpen = "settings.lastAppOpen"
    /// CSV of lead-day ints — @AppStorage doesn't support Set<Int> directly.
    static let leadDaysCSV = "settings.leadDaysCSV"
    static let notifyHour = "settings.notifyHour"
    static let notifyMinute = "settings.notifyMinute"
    static let appearance = "settings.appearance"
    static let darkAccent = "settings.darkAccent"
    static let hasOnboarded = "settings.hasOnboarded"
    /// Legacy key from the removed onboarding categories step.
    /// Older installs may still have a value. Nothing reads it, and onboarding
    /// `finish()` must not write it.
    static let trackedCategoriesCSV = "settings.trackedCategoriesCSV"
    /// Set true when onboarding ends with "Yes, a few" — Library uses it to route.
    static let hasExistingReceipts = "settings.hasExistingReceipts"
    /// Set true once the trial-entry paywall has been shown after onboarding.
    /// Ensures the front-door paywall + explainer sheet fire exactly once per
    /// install — subsequent conversions happen on premium-feature moments.
    static let hasSeenOnboardingPaywall = "settings.hasSeenOnboardingPaywall"
    /// Same key as `FirstSavePayoff.shownKey`. Stamped when the payoff sheet
    /// appears. An ineligible save does not set it.
    static let hasShownFirstSavePayoff = FirstSavePayoff.shownKey
}

enum SettingsDefaults {
    static let notificationsEnabled = true
    static let leadDays: Set<Int> = [14]
    static let notifyHour = 9
    static let notifyMinute = 30
}

/// Canonical lead-day options offered anywhere in the app (onboarding + settings).
/// Used by the scheduler's cancel path to sweep stale IDs when the set changes.
enum LeadDayOption {
    static let all: [Int] = [7, 14, 30]
}

/// Read-only snapshot for services (scheduler, app root) that need current settings
/// without owning the SwiftUI @AppStorage bindings.
enum SettingsSnapshot {
    static var notificationsEnabled: Bool {
        guard UserDefaults.standard.object(forKey: SettingsKeys.notificationsEnabled) != nil else {
            return SettingsDefaults.notificationsEnabled
        }
        return UserDefaults.standard.bool(forKey: SettingsKeys.notificationsEnabled)
    }

    static var leadDaysSet: Set<Int> {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKeys.leadDaysCSV) else {
            return SettingsDefaults.leadDays
        }
        let ints = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return ints.isEmpty ? SettingsDefaults.leadDays : Set(ints)
    }

    static var notifyHour: Int {
        (UserDefaults.standard.object(forKey: SettingsKeys.notifyHour) as? Int) ?? SettingsDefaults.notifyHour
    }

    static var notifyMinute: Int {
        (UserDefaults.standard.object(forKey: SettingsKeys.notifyMinute) as? Int) ?? SettingsDefaults.notifyMinute
    }

    static var appearance: AppearancePreference {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKeys.appearance) else {
            return .system
        }
        return AppearancePreference(rawValue: raw) ?? .system
    }

    static var darkAccent: DarkAccentPreference {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKeys.darkAccent) else {
            return .midnight
        }
        return DarkAccentPreference(rawValue: raw) ?? .midnight
    }

    static var hasOnboarded: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.hasOnboarded)
    }

    static var hasExistingReceipts: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.hasExistingReceipts)
    }

    /// On unless the user turned warranty reminders off. A missing key follows
    /// the older master notifications toggle, which itself defaults to on.
    static var expiryRemindersEnabled: Bool {
        migrateReminderTogglesIfNeeded()
        return UserDefaults.standard.bool(forKey: SettingsKeys.expiryRemindersEnabled)
    }

    static var weeklyReminderEnabled: Bool {
        migrateReminderTogglesIfNeeded()
        return UserDefaults.standard.bool(forKey: SettingsKeys.weeklyReminderEnabled)
    }

    static var lastAppOpen: Date {
        let interval = UserDefaults.standard.double(forKey: SettingsKeys.lastAppOpen)
        guard interval > 0 else { return .now }
        return Date(timeIntervalSince1970: interval)
    }

    static func noteAppOpened(at date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: SettingsKeys.lastAppOpen)
    }

    static func setNotificationsMaster(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingsKeys.notificationsEnabled)
    }

    /// Writes the two reminder toggles the first time, using the existing
    /// notifications switch so an earlier opt-out stays off.
    static func migrateReminderTogglesIfNeeded() {
        let defaults = UserDefaults.standard
        let expiryMissing = defaults.object(forKey: SettingsKeys.expiryRemindersEnabled) == nil
        let weeklyMissing = defaults.object(forKey: SettingsKeys.weeklyReminderEnabled) == nil
        guard expiryMissing || weeklyMissing else { return }
        let master = notificationsEnabled
        if expiryMissing {
            defaults.set(master, forKey: SettingsKeys.expiryRemindersEnabled)
        }
        if weeklyMissing {
            defaults.set(master, forKey: SettingsKeys.weeklyReminderEnabled)
        }
    }
}

extension SettingsSnapshot {
    /// Persist the onboarding answers to app-wide settings. Called once when the flow finishes.
    static func write(leadDays: Set<Int>) {
        let csv = leadDays.sorted().map(String.init).joined(separator: ",")
        UserDefaults.standard.set(csv, forKey: SettingsKeys.leadDaysCSV)
    }

    static func markOnboarded(hasExistingReceipts: Bool) {
        UserDefaults.standard.set(true, forKey: SettingsKeys.hasOnboarded)
        UserDefaults.standard.set(hasExistingReceipts, forKey: SettingsKeys.hasExistingReceipts)
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var detail: String {
        switch self {
        case .system: "Follow iPhone"
        case .light: "Bright and clean"
        case .dark: "Low light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum DarkAccentPreference: String, CaseIterable, Identifiable {
    case defaultBlue = "default"
    case graphite
    case midnight
    case violet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .defaultBlue: "Default"
        case .graphite: "Graphite"
        case .midnight: "Midnight"
        case .violet: "Violet"
        }
    }

    var detail: String {
        switch self {
        case .defaultBlue: "Classic blue"
        case .graphite: "Deep neutral"
        case .midnight: "Dark blue"
        case .violet: "Soft violet"
        }
    }

    var tint: Color {
        switch self {
        case .defaultBlue: .blue
        case .graphite: Color(red: 0.36, green: 0.36, blue: 0.39)
        case .midnight: Color(red: 0.12, green: 0.33, blue: 0.92)
        case .violet: Color(red: 0.52, green: 0.34, blue: 0.95)
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .defaultBlue:
            LinearGradient(
                colors: [
                    Color(red: 0.30, green: 0.60, blue: 1.0),
                    Color(red: 0.00, green: 0.28, blue: 0.75)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .graphite:
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.42, blue: 0.45),
                    Color(red: 0.11, green: 0.11, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .midnight:
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.38, blue: 1.0),
                    Color(red: 0.02, green: 0.06, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .violet:
            LinearGradient(
                colors: [
                    Color(red: 0.68, green: 0.46, blue: 1.0),
                    Color(red: 0.15, green: 0.06, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

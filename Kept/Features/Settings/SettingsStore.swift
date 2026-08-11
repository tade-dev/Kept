import Foundation
import SwiftUI

enum SettingsKeys {
    static let notificationsEnabled = "settings.notificationsEnabled"
    /// CSV of lead-day ints — @AppStorage doesn't support Set<Int> directly.
    static let leadDaysCSV = "settings.leadDaysCSV"
    static let notifyHour = "settings.notifyHour"
    static let notifyMinute = "settings.notifyMinute"
    static let appearance = "settings.appearance"
    static let hasOnboarded = "settings.hasOnboarded"
    /// CSV of TrackedCategory rawValues from onboarding.
    static let trackedCategoriesCSV = "settings.trackedCategoriesCSV"
    /// Set true when onboarding ends with "Yes, a few" — Library uses it to route.
    static let hasExistingReceipts = "settings.hasExistingReceipts"
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

    static var hasOnboarded: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.hasOnboarded)
    }

    static var hasExistingReceipts: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.hasExistingReceipts)
    }
}

extension SettingsSnapshot {
    /// Persist the onboarding answers to app-wide settings. Called once when the flow finishes.
    static func write(leadDays: Set<Int>) {
        let csv = leadDays.sorted().map(String.init).joined(separator: ",")
        UserDefaults.standard.set(csv, forKey: SettingsKeys.leadDaysCSV)
    }

    static func write(trackedCategories: Set<String>) {
        let csv = trackedCategories.sorted().joined(separator: ",")
        UserDefaults.standard.set(csv, forKey: SettingsKeys.trackedCategoriesCSV)
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

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

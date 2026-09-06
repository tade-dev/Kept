import Foundation

/// Pure logic for the "engaged user gets 7 days of Kept Pro on us" flow.
/// Deliberately not a class or observable object — it's a decision function
/// with a small persistence side. Callers (LibraryView) invoke it after
/// mutations that could change the answer (e.g. a new purchase landed).
///
/// Eligibility rule: a user who saved 3 or more receipts within their first
/// 24 hours of using Kept qualifies once. They're not eligible if they're
/// already Pro, if the boost has already been granted, or if the 24-hour
/// window has closed with fewer than 3 purchases.
enum TrialBoostEngagement {
    /// UserDefaults key holding the timestamp of first launch (as seconds
    /// since epoch, `Double`). Set lazily by `noteAppLaunch` on first read.
    static let firstLaunchKey = "kept.firstLaunchAt"

    /// UserDefaults key set once the boost has been granted, so we never
    /// re-trigger.
    static let grantedKey = "kept.trialBoostGranted"

    /// Duration of the engagement window from first launch. Users who don't
    /// hit the threshold inside this window forfeit the bonus.
    static let engagementWindow: TimeInterval = 24 * 60 * 60

    /// Number of purchases the user must save inside the window.
    static let engagementThreshold = 3

    // MARK: - Persistence

    /// Records the current time as first launch if we haven't yet. Idempotent
    /// on subsequent calls. Call this from a hook that runs once per cold
    /// start (e.g. `KeptApp.init()`) so the window starts on the earliest
    /// possible signal.
    static func noteAppLaunch(defaults: UserDefaults = .standard, now: Date = .now) {
        if defaults.double(forKey: firstLaunchKey) == 0 {
            defaults.set(now.timeIntervalSince1970, forKey: firstLaunchKey)
        }
    }

    static func markGranted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: grantedKey)
    }

    static func hasBeenGranted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: grantedKey)
    }

    static func firstLaunchAt(defaults: UserDefaults = .standard) -> Date? {
        let raw = defaults.double(forKey: firstLaunchKey)
        return raw == 0 ? nil : Date(timeIntervalSince1970: raw)
    }

    // MARK: - Decision

    /// Whether we should attempt to grant the boost right now given the
    /// caller's live state. Returns false if: already granted, already Pro,
    /// engagement window has closed, or the purchase count hasn't hit the
    /// threshold yet.
    static func shouldGrant(
        purchaseCount: Int,
        isPro: Bool,
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if isPro { return false }
        if hasBeenGranted(defaults: defaults) { return false }
        guard let firstLaunch = firstLaunchAt(defaults: defaults) else { return false }
        let inWindow = now.timeIntervalSince(firstLaunch) <= engagementWindow
        guard inWindow else { return false }
        return purchaseCount >= engagementThreshold
    }
}

import Foundation
import UserNotifications

/// Local notification scheduler for monetization moments — billing failures,
/// trial/promo endings, trial-boost grants, and the free-tier cap. Fires
/// each moment at most ONCE per install via a latch flag in `UserDefaults`,
/// so users get the nudge without ever feeling pestered.
///
/// Gated on the existing `SettingsKeys.notificationsEnabled` toggle: users
/// who opt out of coverage reminders opt out of offer nudges too. Simpler
/// than a second UI toggle and matches user expectation for "notifications
/// off means notifications off."
///
/// The scheduler assumes notification authorization has already been
/// requested by `CoverageNotificationScheduler.requestAuthorizationIfNeeded()`
/// during onboarding — we don't request permission here, so users who
/// declined the initial ask silently get nothing (correct behaviour).
@MainActor
enum OfferNotificationScheduler {
    private static let center = UNUserNotificationCenter.current()

    // MARK: - Notification IDs

    private enum ID {
        static let billingIssue        = "kept.offer.billingIssue"
        static let proAccessEnding     = "kept.offer.proAccessEnding"
        static let trialBoostGranted   = "kept.offer.trialBoostGranted"
        static let freeCapApproaching  = "kept.offer.freeCapApproaching"
    }

    // MARK: - Latch keys — one per moment, prevents double-firing

    private enum Fired {
        static let billingIssue        = "kept.offer.billingIssueFired"
        static let proAccessEnding     = "kept.offer.proAccessEndingFired"
        static let trialBoostGranted   = "kept.offer.trialBoostGrantedFired"
        static let freeCapApproaching  = "kept.offer.freeCapApproachingFired"
    }

    // MARK: - Preconditions

    private static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.notificationsEnabled)
    }

    private static func hasFired(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    private static func markFired(_ key: String) {
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Billing issue nudge

    /// Schedules "your card was declined, fix it before your Pro pauses" for
    /// ~12 hours after we detected the failure. Gives StoreKit's own retry
    /// mechanism a chance to succeed first (many billing issues self-resolve
    /// within a few hours as banks re-process), so we don't cry wolf.
    static func scheduleBillingIssueNudge(gracePeriodEndsAt: Date?) async {
        guard isEnabled, !hasFired(Fired.billingIssue) else { return }

        let fireAt = Date.now.addingTimeInterval(12 * 60 * 60)
        // If the grace period ends before our 12h delay elapses, fire an
        // hour before the grace end instead of not firing at all.
        let effectiveFire: Date
        if let end = gracePeriodEndsAt, fireAt >= end {
            effectiveFire = max(.now.addingTimeInterval(60), end.addingTimeInterval(-3600))
        } else {
            effectiveFire = fireAt
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Kept Pro paused")
        content.body = String(localized: "Your card was declined. Update it in the App Store to keep Kept Pro active.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        await schedule(id: ID.billingIssue, content: content, at: effectiveFire)
        markFired(Fired.billingIssue)
    }

    /// Cancels the billing-issue nudge (called when RC reports the issue
    /// resolved) and clears the latch so a future billing failure can nudge
    /// again. Different from the other moments where we WANT the once-per-
    /// install semantics — billing issues can genuinely recur.
    static func cancelBillingIssueNudge() {
        center.removePendingNotificationRequests(withIdentifiers: [ID.billingIssue])
        UserDefaults.standard.removeObject(forKey: Fired.billingIssue)
    }

    // MARK: - Pro access ending nudge (Apple trial + promotional grant)

    /// Schedules "your Kept Pro trial ends in 3 days" 3 days before the
    /// expiry. If the expiry is already inside the 3-day window, fires
    /// tomorrow morning instead so the user has some warning.
    static func scheduleProAccessEndingNudge(endsAt: Date, reason: ProAccessExpiry.Reason) async {
        guard isEnabled, !hasFired(Fired.proAccessEnding) else { return }

        let threeDaysOut = endsAt.addingTimeInterval(-3 * 24 * 60 * 60)
        let now = Date.now
        let fireAt: Date
        if threeDaysOut > now.addingTimeInterval(60) {
            fireAt = threeDaysOut
        } else if endsAt > now.addingTimeInterval(3600) {
            // Already inside the lead window — fire soon so we still catch them.
            fireAt = now.addingTimeInterval(60 * 60)
        } else {
            // Less than an hour left; skip — a notification here would land
            // after the fact and feel absurd.
            return
        }

        let content = UNMutableNotificationContent()
        switch reason {
        case .trial:
            content.title = String(localized: "Kept Pro trial ending soon")
            content.body = String(localized: "3 days left on your free trial. Pick a plan to keep unlimited receipts and the claim pack.")
        case .promotional:
            content.title = String(localized: "Your bonus week ends soon")
            content.body = String(localized: "3 days left on the Kept Pro we gave you. Grab a plan to keep it going.")
        }
        content.sound = .default

        await schedule(id: ID.proAccessEnding, content: content, at: fireAt)
        markFired(Fired.proAccessEnding)
    }

    static func cancelProAccessEndingNudge() {
        center.removePendingNotificationRequests(withIdentifiers: [ID.proAccessEnding])
        // Don't clear the latch — a paid conversion or renewal clearing the
        // expiry shouldn't queue up another notification later.
    }

    // MARK: - Trial boost granted nudge

    /// Fired ~4 hours after we granted the boost so it lands as a "later that
    /// day" reminder rather than doubling up with the celebration sheet the
    /// user just saw. Once-per-install.
    static func scheduleTrialBoostGrantedNudge() async {
        guard isEnabled, !hasFired(Fired.trialBoostGranted) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "🎁 Enjoy your week of Kept Pro")
        content.body = String(localized: "Unlimited receipts, claim pack export, and everything else are unlocked for the next 7 days.")
        content.sound = .default

        let fireAt = Date.now.addingTimeInterval(4 * 60 * 60)
        await schedule(id: ID.trialBoostGranted, content: content, at: fireAt)
        markFired(Fired.trialBoostGranted)
    }

    // MARK: - Free-tier cap approaching nudge

    /// Fires ~1 hour after the user's saved-count hits 4 out of 5 free
    /// receipts — a soft "you're one away from the cap, Pro removes it" beat
    /// that doesn't blow up in their face at the moment of save. Once-per-
    /// install; cleared naturally by the latch after firing.
    static func scheduleFreeCapApproachingNudge() async {
        guard isEnabled, !hasFired(Fired.freeCapApproaching) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "One receipt left")
        content.body = String(localized: "You've saved 4 of your 5 free receipts. Kept Pro unlocks unlimited.")
        content.sound = .default

        let fireAt = Date.now.addingTimeInterval(60 * 60)
        await schedule(id: ID.freeCapApproaching, content: content, at: fireAt)
        markFired(Fired.freeCapApproaching)
    }

    // MARK: - Debug reset

    /// Fires the trial-boost celebration nudge in 5 seconds regardless of
    /// the latch — used by the DEBUG menu to actually SEE the OS-level
    /// notification instead of waiting the standard 4 hours after a real
    /// grant. Bypasses `notificationsEnabled` too so a test doesn't need
    /// the reminder toggle flipped on.
    static func fireTrialBoostNudgeSoonForDebug() async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "🎁 Enjoy your week of Kept Pro")
        content.body = String(localized: "Unlimited receipts, claim pack export, and everything else are unlocked for the next 7 days.")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(ID.trialBoostGranted).debug",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        try? await center.add(request)
    }

    /// Removes every offer notification and clears every latch. Not called
    /// from shipping code; exists so a debug menu (or a test) can rehearse
    /// the flows without a fresh install.
    static func resetAllForDebug() {
        center.removePendingNotificationRequests(withIdentifiers: [
            ID.billingIssue,
            ID.proAccessEnding,
            ID.trialBoostGranted,
            ID.freeCapApproaching,
        ])
        for key in [Fired.billingIssue, Fired.proAccessEnding, Fired.trialBoostGranted, Fired.freeCapApproaching] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Plumbing

    private static func schedule(id: String, content: UNMutableNotificationContent, at date: Date) async {
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            // Silent — offer notifications are a bonus, never a failure the
            // user needs to hear about.
        }
    }
}

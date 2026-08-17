import CloudKit
import Foundation
import RevenueCat

/// Configures the RevenueCat SDK exactly once at app launch.
///
/// **App User ID policy (see AGENTS.md / Monetisation):** we use the CloudKit
/// user record ID as the RC App User ID so entitlements survive reinstall and
/// cross-device automatically. We NEVER block launch on the CloudKit fetch:
/// configure anonymously first, then log in when the record ID arrives.
///
/// If iCloud is unavailable at launch, we stay anonymous — and rebind whenever
/// the iCloud account status changes (user signs in later, switches accounts).
@MainActor
enum RevenueCatBootstrap {
    /// Reads `KeptRevenueCatPublicKey` from Info.plist, configures Purchases,
    /// and kicks off the iCloud identity bind. Safe to call multiple times —
    /// Purchases.configure is idempotent per Apple docs.
    static func configure() {
        guard let apiKey = Bundle.main
            .object(forInfoDictionaryKey: "KeptRevenueCatPublicKey") as? String,
              !apiKey.isEmpty,
              apiKey != "appl_REPLACE_ME"
        else {
            // Key missing — likely local dev without Config/RevenueCat.xcconfig.
            // Configure with a placeholder so the SDK doesn't crash on first use,
            // but SubscriptionService.isPro will always report false.
            Purchases.logLevel = .warn
            Purchases.configure(withAPIKey: "appl_placeholder_no_key_configured")
            return
        }

        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)

        Task { await bindICloudIdentity() }

        NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { await bindICloudIdentity() }
        }
    }

    /// Fetches the container-scoped user record ID and calls `Purchases.shared
    /// .logIn(recordName)`. RC's `logIn` is idempotent + aliasing — first call
    /// migrates any anonymous entitlements to the real Customer; subsequent
    /// calls with the same ID are no-ops.
    ///
    /// Silent on failure: iCloud signed out / restricted / offline is normal
    /// state, not an error to surface. We just stay anonymous until the next
    /// `.CKAccountChanged` fires.
    private static func bindICloudIdentity() async {
        do {
            let container = CKContainer.default()
            // Guard on account status FIRST — calling userRecordID() on a
            // signed-out device throws, and we'd never bind if we didn't
            // check first.
            let status = try await container.accountStatus()
            guard status == .available else { return }

            let recordID = try await container.userRecordID()
            let appUserID = recordID.recordName  // stable, opaque, per-iCloud
            _ = try await Purchases.shared.logIn(appUserID)
        } catch {
            // Intentional silent no-op — see doc above.
        }
    }
}

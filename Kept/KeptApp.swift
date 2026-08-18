import SwiftUI
import SwiftData

@main
struct KeptApp: App {
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw: String = AppearancePreference.system.rawValue

    /// Real subscription service, kept alive for the app's lifetime. Injected
    /// into the view hierarchy via `.environment(subscriptionAccess)` so views
    /// see only `SubscriptionAccess` and never import RevenueCat directly.
    @State private var subscriptionAccess: SubscriptionAccess = {
        RevenueCatBootstrap.configure()
        BricolageAppearance.apply()
        return SubscriptionAccess(service: RevenueCatSubscriptionService())
    }()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Purchase.self,
            WarrantyTerm.self,
            PassRecord.self,
        ])
        // `cloudKitDatabase: .automatic` opts the local SwiftData store into
        // CloudKit sync via NSPersistentCloudKitContainer. Every model here
        // has been audited for CloudKit compatibility (every stored property
        // has a default, every relationship optional, no @Attribute(.unique)).
        //
        // Fail-safe: if the user is signed out of iCloud, restricted, or the
        // container is otherwise unavailable, the store still works locally —
        // sync just stays quiet until iCloud comes back. No error banner, no
        // nag. Sync is trust infrastructure, not a feature.
        //
        // Receipt images (@Attribute(.externalStorage)) sync as CKAssets and
        // do not count against the record size budget — they live in the
        // user's own iCloud storage quota.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    private var preferredScheme: ColorScheme? {
        (AppearancePreference(rawValue: appearanceRaw) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(preferredScheme)
                .environment(subscriptionAccess)
        }
        .modelContainer(sharedModelContainer)
    }
}

import SwiftUI
import SwiftData

@main
struct KeptApp: App {
    @State private var subscriptionAccess: SubscriptionAccess = {
        RevenueCatBootstrap.configure()
        BricolageAppearance.apply()
        return SubscriptionAccess(service: RevenueCatSubscriptionService())
    }()

    init() {
        // Anchor the "first 24 hours" engagement window on the earliest
        // possible signal — the very first cold launch. Idempotent on
        // every subsequent launch. Feeds `TrialBoostEngagement.shouldGrant`.
        TrialBoostEngagement.noteAppLaunch()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Purchase.self,
            WarrantyTerm.self,
            PassRecord.self,
        ])
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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(subscriptionAccess)
        }
        .modelContainer(sharedModelContainer)
    }
}

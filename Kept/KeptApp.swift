import SwiftUI
import SwiftData

@main
struct KeptApp: App {
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw: String = AppearancePreference.system.rawValue

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Purchase.self,
            WarrantyTerm.self,
            PassRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

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
        }
        .modelContainer(sharedModelContainer)
    }
}

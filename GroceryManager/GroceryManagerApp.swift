import SwiftUI
import SwiftData

@main
struct GroceryManagerApp: App {
    private let sharedModelContainer = PersistenceController.shared
    @State private var isLaunching = true

    init() {
        LemmaIndexer.install(on: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .opacity(isLaunching ? 0 : 1)
                    .animation(.easeInOut(duration: 0.6), value: isLaunching)

                LaunchScreenView { isLaunching = false }
                    .opacity(isLaunching ? 1 : 0)
                    .scaleEffect(isLaunching ? 1 : 1.08)
                    .animation(.easeInOut(duration: 0.6), value: isLaunching)
                    .allowsHitTesting(isLaunching)
            }
            .task {
                seedDemoDataIfNeeded()
                LemmaIndexer.backfill(sharedModelContainer.mainContext)
                await EntitlementService.shared.refresh()
                await AccountSession.shared.signInFromPurchaseIfNeeded()
                if AccountSession.shared.isSignedIn { await HouseholdSyncService.shared.refreshInvite() }
                await IntentStore.refreshSiriIndex()
            }
        }
        .modelContainer(sharedModelContainer)
    }

    /// First launch on an empty store: load the demo so the whole loop can be tried at once.
    @MainActor
    private func seedDemoDataIfNeeded() {
        let settings = AppSettings.shared
        let context = sharedModelContainer.mainContext
        guard !settings.didSeedDemoData, DemoData.isEmpty(context) else { return }
        DemoData.load(into: context)
        settings.didSeedDemoData = true
    }
}


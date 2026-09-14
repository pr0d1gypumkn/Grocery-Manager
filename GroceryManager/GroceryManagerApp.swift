import SwiftUI
import SwiftData

@main
struct GroceryManagerApp: App {
    private let sharedModelContainer = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

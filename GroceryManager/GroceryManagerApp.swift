import SwiftUI
import SwiftData

@main
struct GroceryManagerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            StorageLocation.self,
            Ingredient.self,
            Recipe.self,
            RecipeIngredient.self
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

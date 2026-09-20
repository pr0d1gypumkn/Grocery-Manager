import SwiftData

enum PersistenceController {
    static let schema = Schema([
        StorageLocation.self,
        Ingredient.self,
        Recipe.self,
        RecipeIngredient.self,
        GroceryItem.self
    ])

    static func makeConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
    }

    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: schema, configurations: [makeConfiguration()])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

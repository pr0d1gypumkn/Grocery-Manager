import SwiftData

enum PersistenceController {
    static let shared: ModelContainer = {
        let schema = Schema([
            StorageLocation.self,
            Ingredient.self,
            Recipe.self,
            RecipeIngredient.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

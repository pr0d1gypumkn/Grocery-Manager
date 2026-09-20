import AppIntents
import Foundation
import SwiftData

private enum GroceryManagerIntentStore {
    static func context() -> ModelContext {
        ModelContext(PersistenceController.shared)
    }
}

struct AddStorageLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Storage Location"
    static let description = IntentDescription("Create a storage location for groceries.")
    static var parameterSummary: some ParameterSummary {
        Summary("Add storage location \(\.$name)")
    }
//    static var allowedExecutionTargets: ExecutionTargets {
//        .main
//    }

    @Parameter(title: "Name", requestValueDialog: "What should the storage location be called?")
    var name: String

    @Parameter(title: "Icon", default: "shippingbox")
    var icon: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = GroceryManagerIntentStore.context()
        context.insert(StorageLocation(name: name, icon: icon))
        try context.save()
        return .result(dialog: "Added the \(name) storage location.")
    }
}

struct RemoveStorageLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Storage Location"
    static let description = IntentDescription("Delete a storage location and its groceries.")
    static var parameterSummary: some ParameterSummary {
        Summary("Remove storage location \(\.$name)")
    }
//    static var allowedExecutionTargets: ExecutionTargets {
//        .main
//    }

    @Parameter(title: "Name", requestValueDialog: "Which storage location should be removed?")
    var name: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = GroceryManagerIntentStore.context()
        let locations = try context.fetch(FetchDescriptor<StorageLocation>())
        guard let location = locations.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            throw IntentError.notFound("storage location \"\(name)\"")
        }
        context.delete(location)
        try context.save()
        return .result(dialog: "Removed the \(location.name) storage location.")
    }
}

struct AddIngredientIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Grocery"
    static let description = IntentDescription("Add a grocery item to inventory.")
    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$name) to inventory")
    }
//    static var allowedExecutionTargets: ExecutionTargets {
//        .main
//    }

    @Parameter(title: "Name", requestValueDialog: "What grocery item do you want to add?")
    var name: String

    @Parameter(title: "Quantity", default: 1)
    var quantity: Double

    @Parameter(title: "Unit", default: "item")
    var unit: String

    @Parameter(title: "Category", default: "Other")
    var category: String

    @Parameter(title: "Expiration date", default: Date.now)
    var expiryDate: Date

    @Parameter(title: "Storage location")
    var locationName: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = GroceryManagerIntentStore.context()
        let locations = try context.fetch(FetchDescriptor<StorageLocation>())
        let location = locationName.flatMap { requestedName in
            locations.first { $0.name.localizedCaseInsensitiveCompare(requestedName) == .orderedSame }
        }
        let ingredient = Ingredient(name: name, quantity: max(quantity, 0), unit: validUnit(unit), category: category, expiryDate: expiryDate, location: location)
        context.insert(ingredient)
        try context.save()
        let locationMessage = location.map { " in \($0.name)" } ?? ""
        return .result(dialog: "Added \(name) to inventory\(locationMessage).")
    }

    private func validUnit(_ value: String) -> String {
        QuantityUnit(rawValue: value.lowercased())?.rawValue ?? "item"
    }
}

struct RemoveIngredientIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Grocery"
    static let description = IntentDescription("Remove a grocery item from inventory by name.")
    static var parameterSummary: some ParameterSummary {
        Summary("Remove \(\.$name) from inventory")
    }
//    static var allowedExecutionTargets: ExecutionTargets {
//        .main
//    }

    @Parameter(title: "Name", requestValueDialog: "Which grocery item should be removed?")
    var name: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = GroceryManagerIntentStore.context()
        let ingredients = try context.fetch(FetchDescriptor<Ingredient>())
        guard let ingredient = ingredients.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            throw IntentError.notFound("grocery \"\(name)\"")
        }
        context.delete(ingredient)
        try context.save()
        return .result(dialog: "Removed \(ingredient.name) from inventory.")
    }
}

struct AddRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Recipe"
    static let description = IntentDescription("Create a recipe with instructions.")
    static var parameterSummary: some ParameterSummary {
        Summary("Add recipe \(\.$name)")
    }
//    static var allowedExecutionTargets: ExecutionTargets {
//        .main
//    }

    @Parameter(title: "Name", requestValueDialog: "What is the recipe name?")
    var name: String

    @Parameter(title: "Instructions", default: "")
    var instructions: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = GroceryManagerIntentStore.context()
        context.insert(Recipe(name: name, instructions: instructions))
        try context.save()
        return .result(dialog: "Added the \(name) recipe.")
    }
}

struct RemoveRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Recipe"
    static let description = IntentDescription("Delete a recipe by name.")
    static var parameterSummary: some ParameterSummary {
        Summary("Remove recipe \(\.$name)")
    }
//    static var allowedExecutionTargets: ExecutionTargets {
//        .main
//    }

    @Parameter(title: "Name", requestValueDialog: "Which recipe should be removed?")
    var name: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = GroceryManagerIntentStore.context()
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        guard let recipe = recipes.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            throw IntentError.notFound("recipe \"\(name)\"")
        }
        context.delete(recipe)
        try context.save()
        return .result(dialog: "Removed the \(recipe.name) recipe.")
    }
}


struct RecipeEntity: AppEntity {
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Recipe"
    static var defaultQuery = RecipeQuery()
    
    // Unique identifier mapped directly from your unique Recipe name
    let id: String
    
    @Property(title: "Name")
    var name: String
    
    @Property(title: "Instructions")
    var instructions: String
    
    @Property(title: "Ingredients List")
    var ingredientsSummary: [String]

    // FIX 3: Fixed the stringLiteral instantiation to compile natively in Swift 6
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: "\(ingredientsSummary.count) ingredients required")
        )
    }
    
    @MainActor
    init(from model: Recipe) {
        self.id = model.name
        self.name = model.name
        self.instructions = model.instructions
        self.ingredientsSummary = model.ingredients.map { "\($0.requiredQuantity) \($0.unit) of \($0.name)" }
    }
}

struct RecipeQuery: EntityQuery {
    
    // Helps Apple Intelligence search or autocomplete recipes by name string
    @MainActor
    func entities(matching string: String) async throws -> [RecipeEntity] {
        let context = ModelContext(PersistenceController.shared)

        let descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.name.localizedStandardContains(string) }
        )

        let matches = try context.fetch(descriptor)
        return matches.map { RecipeEntity(from: $0) }
    }

    // Resolves concrete entities when Siri points to a specific recipe selection
    @MainActor
    func entities(for identifiers: [String]) async throws -> [RecipeEntity] {
        let context = ModelContext(PersistenceController.shared)

        let descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { identifiers.contains($0.name) }
        )

        let matches = try context.fetch(descriptor)
        return matches.map { RecipeEntity(from: $0) }
    }

    // Provides suggested recipes (e.g. recent or most popular)
    @MainActor
    func suggestedEntities() async throws -> [RecipeEntity] {
        let context = ModelContext(PersistenceController.shared)

        let descriptor = FetchDescriptor<Recipe>()
        let matches = try context.fetch(descriptor)
        return matches.map { RecipeEntity(from: $0) }
    }
}



struct CheckRecipeIngredientsIntent: AppIntent, Sendable {
    // Custom intents give Apple Intelligence full context when named properly
    static var title: LocalizedStringResource = "Check Recipe Ingredients"
    
    // Let the system understand what this intent handles
    static var description = IntentDescription("Displays the ingredients needed to cook a saved recipe.")

    // This makes the action fully discoverable by Spotlight and Siri
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Recipe")
    var targetRecipe: RecipeEntity

    @MainActor
    func perform() async throws -> some ReturnsValue<[String]> & ProvidesDialog {
        let dialogOutput = "For \(targetRecipe.name), you will need: \(targetRecipe.ingredientsSummary.joined(separator: ", "))."
        
        return .result(
            value: targetRecipe.ingredientsSummary,
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogOutput))
        )
    }
}


struct CheckRecipesIntent: AppIntent, Sendable {
    static var title: LocalizedStringResource = "Check Recipes"
    
    static var description = IntentDescription("Displays a list of saved recipes")
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some ReturnsValue<[RecipeEntity]> & ProvidesDialog {
        let query = RecipeQuery()
        let recipes: [RecipeEntity]
        
        recipes = try await query.suggestedEntities()
        
        return .result(
            value: recipes,
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: "Found \(recipes.count) recipes: \n\(recipes.map {$0.name}.joined(separator: ", "))"))
        )
        
    }
}

enum IntentError: LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let item): "Could not find \(item)."
        }
    }
}

struct GroceryManagerShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddStorageLocationIntent(), phrases: [AppShortcutPhrase<AddStorageLocationIntent>("Add a storage location in \(.applicationName)")], shortTitle: LocalizedStringResource("Add Location"), systemImageName: "archivebox.badge.plus")
        AppShortcut(intent: RemoveStorageLocationIntent(), phrases: [AppShortcutPhrase<RemoveStorageLocationIntent>("Remove a storage location in \(.applicationName)")], shortTitle: LocalizedStringResource("Remove Location"), systemImageName: "archivebox.badge.minus")
        AppShortcut(intent: AddIngredientIntent(), phrases: [AppShortcutPhrase<AddIngredientIntent>("Add a grocery item in \(.applicationName)")], shortTitle: LocalizedStringResource("Add Grocery"), systemImageName: "cart.badge.plus")
        AppShortcut(intent: RemoveIngredientIntent(), phrases: [AppShortcutPhrase<RemoveIngredientIntent>("Remove a grocery item in \(.applicationName)")], shortTitle: LocalizedStringResource("Remove Grocery"), systemImageName: "cart.badge.minus")
        AppShortcut(intent: AddRecipeIntent(), phrases: [AppShortcutPhrase<AddRecipeIntent>("Add a recipe in \(.applicationName)")], shortTitle: LocalizedStringResource("Add Recipe"), systemImageName: "book.pages")
        AppShortcut(intent: RemoveRecipeIntent(), phrases: [AppShortcutPhrase<RemoveRecipeIntent>("Remove a recipe in \(.applicationName)")], shortTitle: LocalizedStringResource("Remove Recipe"), systemImageName: "book.pages.fill")
        AppShortcut(
            intent: CheckRecipeIngredientsIntent(),
            phrases: [
                "Check ingredients for \(.applicationName)",
                "What do I need for a recipe in \(.applicationName)",
                "Look up recipe ingredients with \(.applicationName)"
            ],
            shortTitle: "Check Recipe Ingredients",
            systemImageName: "fork.knife"
        )
        AppShortcut(intent: CheckRecipesIntent(),
                    phrases: [
                        AppShortcutPhrase<CheckRecipesIntent>("Check recipes in \(.applicationName)"),
                        AppShortcutPhrase<CheckRecipesIntent>("What recipes are available in \(.applicationName)")
                    ],
                    shortTitle: LocalizedStringResource("Check Recipes"),
                    systemImageName: "book.pages")
    }
}


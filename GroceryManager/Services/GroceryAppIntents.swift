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
        let existing = try context.fetch(FetchDescriptor<StorageLocation>())
        if existing.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return .result(dialog: "You already have a \(name) storage location.")
        }
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
        let existing = try context.fetch(FetchDescriptor<Recipe>())
        if existing.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return .result(dialog: "You already have a recipe called \(name).")
        }
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


struct RecipeEntity: IndexedEntity {
    
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

/// `EntityStringQuery` (not plain `EntityQuery`) so Siri can resolve a spoken recipe name.
struct RecipeQuery: EntityStringQuery {
    
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

/// App Shortcuts work with Siri as soon as the app is installed — no setup.
/// Apple allows at most 10, so these cover everyday voice tasks. Every other intent
/// (storage locations, adding/removing recipes, etc.) is still available to Siri and
/// in the Shortcuts app; it just doesn't have its own fixed phrase.
struct GroceryManagerShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .orange

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MealPlanForDayIntent(),
            phrases: [
                "What's for dinner in \(.applicationName)",
                "What's on my meal plan in \(.applicationName)",
                "What am I eating today in \(.applicationName)",
                "\(.applicationName) meal plan"
            ],
            shortTitle: "Today's Meals",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: PlanMealIntent(),
            phrases: [
                "Plan \(\.$recipe) in \(.applicationName)",
                "Add \(\.$recipe) to my meal plan in \(.applicationName)",
                "Plan a meal in \(.applicationName)"
            ],
            shortTitle: "Plan a Meal",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: CookMealIntent(),
            phrases: [
                "I cooked \(\.$meal) in \(.applicationName)",
                "Mark a meal as cooked in \(.applicationName)"
            ],
            shortTitle: "Cook Meal",
            systemImageName: "frying.pan"
        )
        AppShortcut(
            intent: ShopForMealPlanIntent(),
            phrases: [
                "Shop for my meal plan in \(.applicationName)",
                "Add missing ingredients to my list in \(.applicationName)"
            ],
            shortTitle: "Shop for Meal Plan",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: AddToGroceryListIntent(),
            phrases: [
                "Add to my grocery list in \(.applicationName)",
                "Add to my shopping list in \(.applicationName)"
            ],
            shortTitle: "Add to List",
            systemImageName: "text.badge.plus"
        )
        AppShortcut(
            intent: ReadGroceryListIntent(),
            phrases: [
                "What's on my grocery list in \(.applicationName)",
                "Read my shopping list in \(.applicationName)"
            ],
            shortTitle: "Grocery List",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: CheckStockIntent(),
            phrases: [
                "How much \(\.$item) do I have in \(.applicationName)",
                "Check my \(\.$item) in \(.applicationName)",
                "Check stock in \(.applicationName)"
            ],
            shortTitle: "Check Stock",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: UseStockIntent(),
            phrases: [
                "I used \(\.$item) in \(.applicationName)",
                "Use some \(\.$item) in \(.applicationName)",
                "Log what I used in \(.applicationName)"
            ],
            shortTitle: "Use Stock",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: ExpiringSoonIntent(),
            phrases: [
                "What's expiring in \(.applicationName)",
                "What should I use up in \(.applicationName)"
            ],
            shortTitle: "Expiring Soon",
            systemImageName: "clock.badge.exclamationmark"
        )
        AppShortcut(
            intent: WhatCanICookIntent(),
            phrases: [
                "What can I cook in \(.applicationName)",
                "What can I make in \(.applicationName)"
            ],
            shortTitle: "What Can I Cook",
            systemImageName: "fork.knife"
        )
    }
}

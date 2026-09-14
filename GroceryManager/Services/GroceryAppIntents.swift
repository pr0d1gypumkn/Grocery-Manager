import AppIntents
import Foundation
import SwiftData

struct AddStorageLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Storage Location"
    static let description = IntentDescription("Create a storage location for groceries.")

    @Parameter(title: "Name") var name: String
    @Parameter(title: "Icon", default: "shippingbox") var icon: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(PersistenceController.shared)
        context.insert(StorageLocation(name: name, icon: icon))
        try context.save()
        return .result(dialog: "Added the \(name) storage location.")
    }
}

struct RemoveStorageLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Storage Location"
    static let description = IntentDescription("Delete a storage location and its groceries.")

    @Parameter(title: "Name") var name: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(PersistenceController.shared)
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

    @Parameter(title: "Name") var name: String
    @Parameter(title: "Quantity") var quantity: Double
    @Parameter(title: "Unit", default: "item") var unit: String
    @Parameter(title: "Category", default: "Other") var category: String
    @Parameter(title: "Expiration date", default: Date.now) var expiryDate: Date
    @Parameter(title: "Storage location") var locationName: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(PersistenceController.shared)
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

    @Parameter(title: "Name") var name: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(PersistenceController.shared)
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

    @Parameter(title: "Name") var name: String
    @Parameter(title: "Instructions", default: "") var instructions: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(PersistenceController.shared)
        context.insert(Recipe(name: name, instructions: instructions))
        try context.save()
        return .result(dialog: "Added the \(name) recipe.")
    }
}

struct RemoveRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Recipe"
    static let description = IntentDescription("Delete a recipe by name.")

    @Parameter(title: "Name") var name: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(PersistenceController.shared)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        guard let recipe = recipes.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            throw IntentError.notFound("recipe \"\(name)\"")
        }
        context.delete(recipe)
        try context.save()
        return .result(dialog: "Removed the \(recipe.name) recipe.")
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
        AppShortcut(intent: AddIngredientIntent(), phrases: [AppShortcutPhrase<AddIngredientIntent>("Add a grocery in \(.applicationName)")], shortTitle: LocalizedStringResource("Add Grocery"), systemImageName: "cart.badge.plus")
        AppShortcut(intent: RemoveIngredientIntent(), phrases: [AppShortcutPhrase<RemoveIngredientIntent>("Remove a grocery in \(.applicationName)")], shortTitle: LocalizedStringResource("Remove Grocery"), systemImageName: "cart.badge.minus")
        AppShortcut(intent: AddRecipeIntent(), phrases: [AppShortcutPhrase<AddRecipeIntent>("Add a recipe in \(.applicationName)")], shortTitle: LocalizedStringResource("Add Recipe"), systemImageName: "book.pages")
        AppShortcut(intent: RemoveRecipeIntent(), phrases: [AppShortcutPhrase<RemoveRecipeIntent>("Remove a recipe in \(.applicationName)")], shortTitle: LocalizedStringResource("Remove Recipe"), systemImageName: "book.pages.fill")
    }
}
import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

// Siri control for meal planning, stock and the grocery list.
//
// Every intent here is a self-describing action (title, description, typed parameters,
// returned values) so Siri can call it from natural requests ("I used the last of
// the milk", "what's for dinner tomorrow?") as well as from the App Shortcut phrases
// in `GroceryManagerShortcuts`.
//
// iOS 27.3: per the 27.3 beta reports, Siri AI calls existing App Intents as tools, and
// may also need an explicit "tool" annotation. That annotation isn't in the iOS 27.2 SDK
// this project builds with, so it isn't applied yet. Once you build with the 27.3 SDK,
// add it to the intents below, following Apple's 27.3 docs.

// MARK: - Shared helpers

@MainActor
enum IntentStore {
    /// The app's main context, so changes made by Siri show up immediately in open screens.
    static var context: ModelContext { PersistenceController.shared.mainContext }

    static func encode(_ id: PersistentIdentifier) -> String {
        (try? JSONEncoder().encode(id))?.base64EncodedString() ?? ""
    }

    static func decode(_ string: String) -> PersistentIdentifier? {
        guard let data = Data(base64Encoded: string) else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }

    static func models<T: PersistentModel>(_ type: T.Type, ids: [String]) -> [T] {
        let wanted = Set(ids.compactMap(decode))
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return all.filter { wanted.contains($0.persistentModelID) }
    }

    /// Refreshes Spotlight's semantic index and App Shortcut parameter values so Siri
    /// knows the names of the user's recipes and stock. Call after launch.
    static func refreshSiriIndex() async {
        let recipes = ((try? context.fetch(FetchDescriptor<Recipe>())) ?? []).map(RecipeEntity.init(from:))
        let stock = ((try? context.fetch(FetchDescriptor<Ingredient>())) ?? []).map(StockItemEntity.init(from:))
        try? await CSSearchableIndex.default().indexAppEntities(recipes)
        try? await CSSearchableIndex.default().indexAppEntities(stock)
        GroceryManagerShortcuts.updateAppShortcutParameters()
    }
}

private extension Double {
    var spoken: String { formatted(.number.precision(.fractionLength(0...2))) }
}

private func listSentence(_ items: [String]) -> String {
    items.formatted(.list(type: .and))
}

// MARK: - Enums

extension MealType: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
    static let caseDisplayRepresentations: [MealType: DisplayRepresentation] = [
        .breakfast: DisplayRepresentation(title: "Breakfast", image: .init(systemName: "sunrise.fill")),
        .lunch: DisplayRepresentation(title: "Lunch", image: .init(systemName: "sun.max.fill")),
        .dinner: DisplayRepresentation(title: "Dinner", image: .init(systemName: "moon.stars.fill")),
        .snack: DisplayRepresentation(title: "Snack", image: .init(systemName: "carrot.fill"))
    ]
}

extension QuantityUnit: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Unit"
    static let caseDisplayRepresentations: [QuantityUnit: DisplayRepresentation] = [
        .item: "Items",
        .dozen: "Dozen",
        .grams: "Grams",
        .kilograms: "Kilograms",
        .milliliters: "Millilitres",
        .liters: "Litres",
        .ounces: "Ounces",
        .pounds: "Pounds",
        .fluidOunces: "Fluid ounces",
        .teaspoons: "Teaspoons",
        .tablespoons: "Tablespoons",
        .cups: "Cups",
        .pints: "Pints",
        .quarts: "Quarts",
        .gallons: "Gallons",
        .pinches: "Pinches",
        .dashes: "Dashes",
        .smidgens: "Smidgens",
        .serving: "Servings"
    ]
}

// MARK: - Entities

/// Something in the user's kitchen: an `Ingredient` row with a quantity and expiry date.
struct StockItemEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Stock Item",
        numericFormat: "\(placeholder: .int) stock items"
    )
    static let defaultQuery = StockItemQuery()

    let id: String

    @Property(title: "Name") var name: String
    @Property(title: "Quantity") var quantity: Double
    @Property(title: "Unit") var unit: String
    @Property(title: "Category") var category: String
    @Property(title: "Expiry Date") var expiryDate: Date
    @Property(title: "Storage Location") var locationName: String?
    @Property(title: "Running Low") var isLow: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(quantity.spoken) \(unit)\(locationName.map { " · \($0)" } ?? "")",
            image: .init(systemName: "shippingbox")
        )
    }

    @MainActor
    init(from model: Ingredient) {
        id = IntentStore.encode(model.persistentModelID)
        name = model.name
        quantity = model.quantity
        unit = model.unit
        category = model.category
        expiryDate = model.expiryDate
        locationName = model.location?.name
        isLow = InventoryViewModel.isLowStock(model)
    }
}

struct StockItemQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [StockItemEntity] {
        IntentStore.models(Ingredient.self, ids: identifiers).map(StockItemEntity.init(from:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [StockItemEntity] {
        let all = (try? IntentStore.context.fetch(FetchDescriptor<Ingredient>())) ?? []
        return all
            .filter { $0.name.localizedStandardContains(string) || IngredientNameMatcher.matches($0.name, string) }
            .map(StockItemEntity.init(from:))
    }

    @MainActor
    func suggestedEntities() async throws -> [StockItemEntity] {
        let all = (try? IntentStore.context.fetch(FetchDescriptor<Ingredient>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return all.map(StockItemEntity.init(from:))
    }
}

struct GroceryItemEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Grocery List Item"
    static let defaultQuery = GroceryItemQuery()

    let id: String

    @Property(title: "Name") var name: String
    @Property(title: "Quantity") var quantity: Double
    @Property(title: "Unit") var unit: String
    @Property(title: "In Basket") var isChecked: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(quantity.spoken) \(unit)",
            image: .init(systemName: isChecked ? "checkmark.circle.fill" : "circle")
        )
    }

    @MainActor
    init(from model: GroceryItem) {
        id = IntentStore.encode(model.persistentModelID)
        name = model.name
        quantity = model.quantity
        unit = model.unit
        isChecked = model.isChecked
    }
}

struct GroceryItemQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [GroceryItemEntity] {
        IntentStore.models(GroceryItem.self, ids: identifiers).map(GroceryItemEntity.init(from:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [GroceryItemEntity] {
        let all = (try? IntentStore.context.fetch(FetchDescriptor<GroceryItem>())) ?? []
        return all
            .filter { $0.name.localizedStandardContains(string) || IngredientNameMatcher.matches($0.name, string) }
            .map(GroceryItemEntity.init(from:))
    }

    @MainActor
    func suggestedEntities() async throws -> [GroceryItemEntity] {
        let all = (try? IntentStore.context.fetch(FetchDescriptor<GroceryItem>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return all.filter { !$0.isChecked }.map(GroceryItemEntity.init(from:))
    }
}

struct PlannedMealEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Planned Meal"
    static let defaultQuery = PlannedMealQuery()

    let id: String

    @Property(title: "Recipe") var recipeName: String
    @Property(title: "Day") var date: Date
    @Property(title: "Meal") var mealType: MealType
    @Property(title: "Servings") var servings: Int
    @Property(title: "Cooked") var isCooked: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(recipeName)",
            subtitle: "\(mealType.rawValue), \(date.formatted(.dateTime.weekday(.wide).month().day()))",
            image: .init(systemName: mealType.symbol)
        )
    }

    @MainActor
    init(from model: MealPlanEntry) {
        id = IntentStore.encode(model.persistentModelID)
        recipeName = model.recipe?.name ?? "Meal"
        date = model.date
        mealType = model.mealType
        servings = model.servings
        isCooked = model.isCooked
    }
}

struct PlannedMealQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PlannedMealEntity] {
        IntentStore.models(MealPlanEntry.self, ids: identifiers).map(PlannedMealEntity.init(from:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [PlannedMealEntity] {
        try await suggestedEntities().filter { $0.recipeName.localizedStandardContains(string) }
    }

    /// Uncooked meals from yesterday through the next week, soonest first.
    @MainActor
    func suggestedEntities() async throws -> [PlannedMealEntity] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now)) ?? .now
        let end = calendar.date(byAdding: .day, value: 8, to: start) ?? .now
        let descriptor = FetchDescriptor<MealPlanEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end && !$0.isCooked },
            sortBy: [SortDescriptor(\.date)]
        )
        return ((try? IntentStore.context.fetch(descriptor)) ?? []).map(PlannedMealEntity.init(from:))
    }
}

// MARK: - Grocery list

struct AddToGroceryListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Grocery List"
    static let description = IntentDescription(
        "Adds an item to the shopping list. If it's already on the list, its amount is updated.",
        categoryName: "Grocery List"
    )
    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$quantity) \(\.$unit) of \(\.$name) to the grocery list")
    }

    @Parameter(title: "Item", requestValueDialog: "What should I add to your grocery list?")
    var name: String

    @Parameter(title: "Quantity", default: 1)
    var quantity: Double

    @Parameter(title: "Unit", default: .item)
    var unit: QuantityUnit

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<GroceryItemEntity> & ProvidesDialog {
        GroceryViewModel(modelContext: IntentStore.context)
            .saveGrocery(existing: nil, name: name, quantity: quantity, unit: unit.rawValue, category: nil)
        let saved = ((try? IntentStore.context.fetch(FetchDescriptor<GroceryItem>())) ?? [])
            .first { $0.name.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame }
        guard let saved else { throw IntentError.notFound("\"\(name)\"") }
        let amount = unit == .item ? quantity.spoken : "\(quantity.spoken) \(unit.rawValue)"
        return .result(value: GroceryItemEntity(from: saved), dialog: "Added \(amount) \(saved.name) to your grocery list.")
    }
}

struct ReadGroceryListIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Grocery List"
    static let description = IntentDescription(
        "Lists what's still left to buy on the grocery list.",
        categoryName: "Grocery List"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[GroceryItemEntity]> & ProvidesDialog {
        let items = try await GroceryItemQuery().suggestedEntities()
        guard !items.isEmpty else {
            return .result(value: [], dialog: "Your grocery list is empty.")
        }
        let names = items.map { $0.quantity == 1 && $0.unit == "item" ? $0.name : "\($0.quantity.spoken) \($0.unit) \($0.name)" }
        return .result(value: items, dialog: "You have \(items.count) things to buy: \(listSentence(names)).")
    }
}

struct CheckOffGroceryIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Off Grocery Item"
    static let description = IntentDescription(
        "Marks an item on the grocery list as picked up.",
        categoryName: "Grocery List"
    )
    static var parameterSummary: some ParameterSummary {
        Summary("Check off \(\.$item)")
    }

    @Parameter(title: "Item", requestValueDialog: "Which item did you pick up?")
    var item: GroceryItemEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = IntentStore.models(GroceryItem.self, ids: [item.id]).first else {
            throw IntentError.notFound(item.name)
        }
        if !model.isChecked {
            GroceryViewModel(modelContext: IntentStore.context).toggleChecked(model)
        }
        return .result(dialog: "Checked off \(model.name).")
    }
}

// MARK: - Stock

struct CheckStockIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Stock"
    static let description = IntentDescription(
        "Tells you how much of an item you have at home and when it expires.",
        categoryName: "Stock"
    )
    static var parameterSummary: some ParameterSummary {
        Summary("How much \(\.$item) do I have?")
    }

    @Parameter(title: "Item", requestValueDialog: "Which item should I check?")
    var item: StockItemEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<StockItemEntity> & ProvidesDialog {
        guard let model = IntentStore.models(Ingredient.self, ids: [item.id]).first else {
            throw IntentError.notFound(item.name)
        }
        let fresh = StockItemEntity(from: model)
        let place = fresh.locationName.map { " in the \($0)" } ?? ""
        let expiry = fresh.expiryDate.formatted(.relative(presentation: .named))
        let low = fresh.isLow ? " You're running low." : ""
        return .result(
            value: fresh,
            dialog: "You have \(fresh.quantity.spoken) \(fresh.unit) of \(fresh.name)\(place). It expires \(expiry).\(low)"
        )
    }
}

struct UseStockIntent: AppIntent {
    static let title: LocalizedStringResource = "Use Stock"
    static let description = IntentDescription(
        "Records that you used some of an item. If it drops to its reorder level it's added to the grocery list.",
        categoryName: "Stock"
    )
    static var parameterSummary: some ParameterSummary {
        Summary("Use \(\.$amount) of \(\.$item)")
    }

    @Parameter(title: "Item", requestValueDialog: "What did you use?")
    var item: StockItemEntity

    @Parameter(title: "Amount", description: "How much was used, in the item's own unit.", default: 1)
    var amount: Double

    @Parameter(title: "Used it all", default: false)
    var usedAll: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<StockItemEntity> & ProvidesDialog {
        guard let model = IntentStore.models(Ingredient.self, ids: [item.id]).first else {
            throw IntentError.notFound(item.name)
        }
        let context = IntentStore.context
        InventoryViewModel(modelContext: context).adjust(model, by: usedAll ? -model.quantity : -amount)

        var dialog = "Updated \(model.name). \(model.quantity.spoken) \(model.unit) left."
        if InventoryViewModel.isLowStock(model) {
            let alreadyListed = ((try? context.fetch(FetchDescriptor<GroceryItem>())) ?? [])
                .contains { IngredientNameMatcher.matches($0.name, model.name) && !$0.isChecked }
            if !alreadyListed {
                let needed = max(model.initialQuantity - model.quantity, 1)
                GroceryViewModel(modelContext: context)
                    .saveGrocery(existing: nil, name: model.name, quantity: needed, unit: model.unit, category: model.category)
            }
            dialog += " It's running low, so it's on your grocery list."
        }
        return .result(value: StockItemEntity(from: model), dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct RestockIntent: AppIntent {
    static let title: LocalizedStringResource = "Restock Item"
    static let description = IntentDescription(
        "Adds to the amount of something you already keep in stock, or refills it to its usual amount.",
        categoryName: "Stock"
    )
    static var parameterSummary: some ParameterSummary {
        When(\.$refillToFull, .equalTo, true) {
            Summary("Refill \(\.$item) to its usual amount") { \.$refillToFull }
        } otherwise: {
            Summary("Add \(\.$amount) to \(\.$item)") { \.$refillToFull }
        }
    }

    @Parameter(title: "Item", requestValueDialog: "What did you restock?")
    var item: StockItemEntity

    @Parameter(title: "Amount", default: 1)
    var amount: Double

    @Parameter(title: "Refill to usual amount", default: false)
    var refillToFull: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<StockItemEntity> & ProvidesDialog {
        guard let model = IntentStore.models(Ingredient.self, ids: [item.id]).first else {
            throw IntentError.notFound(item.name)
        }
        let viewModel = InventoryViewModel(modelContext: IntentStore.context)
        if refillToFull {
            viewModel.refill(model)
        } else {
            viewModel.adjust(model, by: amount)
        }
        return .result(
            value: StockItemEntity(from: model),
            dialog: "You now have \(model.quantity.spoken) \(model.unit) of \(model.name)."
        )
    }
}

struct ExpiringSoonIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Expiring"
    static let description = IntentDescription(
        "Lists food that has expired or expires within the given number of days.",
        categoryName: "Stock"
    )
    static var parameterSummary: some ParameterSummary {
        Summary("What expires in the next \(\.$days) days?")
    }

    @Parameter(title: "Days", default: 3, inclusiveRange: (0, 30))
    var days: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[StockItemEntity]> & ProvidesDialog {
        let cutoff = Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
        let descriptor = FetchDescriptor<Ingredient>(
            predicate: #Predicate { $0.expiryDate <= cutoff && $0.quantity > 0 },
            sortBy: [SortDescriptor(\.expiryDate)]
        )
        let items = ((try? IntentStore.context.fetch(descriptor)) ?? []).map(StockItemEntity.init(from:))
        guard !items.isEmpty else {
            return .result(value: [], dialog: "Nothing expires in the next \(days) days.")
        }
        let phrases = items.prefix(8).map { item in
            item.expiryDate < .now
                ? "\(item.name) (expired)"
                : "\(item.name) \(item.expiryDate.formatted(.relative(presentation: .named)))"
        }
        return .result(value: items, dialog: "Use these soon: \(listSentence(Array(phrases))).")
    }
}

// MARK: - Meal planning

struct PlanMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Plan a Meal"
    static let description = IntentDescription(
        "Adds a recipe to the meal plan for a day and meal, and says if anything needs buying.",
        categoryName: "Meal Plan"
    )
    static var parameterSummary: some ParameterSummary {
        Summary("Plan \(\.$recipe) for \(\.$mealType) on \(\.$date)") {
            \.$servings
        }
    }

    @Parameter(title: "Recipe", requestValueDialog: "Which recipe?")
    var recipe: RecipeEntity

    @Parameter(title: "Day", description: "Defaults to today.", kind: .date)
    var date: Date?

    @Parameter(title: "Meal", default: .dinner)
    var mealType: MealType

    @Parameter(title: "Servings", description: "Defaults to the recipe's servings.", inclusiveRange: (1, 24))
    var servings: Int?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PlannedMealEntity> & ProvidesDialog {
        let context = IntentStore.context
        guard let model = ((try? context.fetch(FetchDescriptor<Recipe>())) ?? []).first(where: { $0.name == recipe.id }) else {
            throw IntentError.notFound("recipe \"\(recipe.name)\"")
        }
        let day = Calendar.current.startOfDay(for: date ?? .now)
        MealPlanViewModel(modelContext: context)
            .addMeal(recipe: model, on: day, mealType: mealType, servings: servings ?? model.servings)

        let entry = ((try? context.fetch(FetchDescriptor<MealPlanEntry>())) ?? [])
            .last { $0.recipe == model && $0.date == day && $0.mealType == mealType }
        guard let entry else { throw IntentError.notFound("the planned meal") }

        let inventory = (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []
        let missing = PantryMatcher()
            .matches(requirements: MealPlanViewModel.requirements(for: [entry]), inventory: inventory)
            .filter { !$0.isInStock }
            .map(\.requiredName)
        let when = day.formatted(.relative(presentation: .named, unitsStyle: .wide))
        let stock = missing.isEmpty ? "You have everything you need." : "You'll need to buy \(listSentence(missing))."
        return .result(
            value: PlannedMealEntity(from: entry),
            dialog: "Planned \(model.name) for \(mealType.rawValue.lowercased()) \(when). \(stock)"
        )
    }
}

struct MealPlanForDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Meal Plan"
    static let description = IntentDescription(
        "Says what's planned to eat on a day, such as \"what's for dinner tonight?\".",
        categoryName: "Meal Plan"
    )
    static var parameterSummary: some ParameterSummary {
        Summary("Get the meal plan for \(\.$date)") { \.$mealType }
    }

    @Parameter(title: "Day", description: "Defaults to today.", kind: .date)
    var date: Date?

    @Parameter(title: "Meal", description: "Leave empty for the whole day.")
    var mealType: MealType?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[PlannedMealEntity]> & ProvidesDialog {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date ?? .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<MealPlanEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        let entries = ((try? IntentStore.context.fetch(descriptor)) ?? [])
            .filter { mealType == nil || $0.mealType == mealType }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }

        let when = calendar.isDateInToday(start) ? "today" : start.formatted(.dateTime.weekday(.wide))
        guard !entries.isEmpty else {
            let what = mealType.map { "for \($0.rawValue.lowercased())" } ?? ""
            return .result(value: [], dialog: "Nothing is planned \(what) \(when).")
        }
        let phrases = entries.map { "\($0.mealType.rawValue.lowercased()) is \($0.recipe?.name ?? "unnamed")" }
        return .result(
            value: entries.map(PlannedMealEntity.init(from:)),
            dialog: "For \(when), \(listSentence(phrases))."
        )
    }
}

struct CookMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Cook Planned Meal"
    static let description = IntentDescription(
        "Marks a planned meal as cooked and subtracts its ingredients from stock.",
        categoryName: "Meal Plan"
    )
    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$meal) as cooked")
    }

    @Parameter(title: "Meal", requestValueDialog: "Which meal did you cook?")
    var meal: PlannedMealEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentStore.context
        guard let entry = IntentStore.models(MealPlanEntry.self, ids: [meal.id]).first else {
            throw IntentError.notFound(meal.recipeName)
        }
        guard !entry.isCooked else {
            return .result(dialog: "\(meal.recipeName) is already marked as cooked.")
        }
        let inventory = (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []
        let shortfalls = MealPlanViewModel(modelContext: context).markCooked(entry, inventory: inventory)
        let note = shortfalls.isEmpty ? "" : " You were short on \(listSentence(shortfalls))."
        return .result(dialog: "Enjoy! I've taken the ingredients for \(meal.recipeName) out of your stock.\(note)")
    }
}

struct ShopForMealPlanIntent: AppIntent {
    static let title: LocalizedStringResource = "Shop for Meal Plan"
    static let description = IntentDescription(
        "Adds everything the upcoming planned meals need, but you don't have, to the grocery list.",
        categoryName: "Meal Plan"
    )
    static var parameterSummary: some ParameterSummary {
        Summary("Add missing ingredients for the next \(\.$days) days to the grocery list")
    }

    @Parameter(title: "Days", default: 7, inclusiveRange: (1, 31))
    var days: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[GroceryItemEntity]> & ProvidesDialog {
        let context = IntentStore.context
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let entries = (try? context.fetch(FetchDescriptor<MealPlanEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end && !$0.isCooked }
        ))) ?? []
        guard !entries.isEmpty else {
            return .result(value: [], dialog: "There are no meals planned for the next \(days) days.")
        }
        let inventory = (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []
        let missingNames = PantryMatcher()
            .matches(requirements: MealPlanViewModel.requirements(for: entries), inventory: inventory)
            .filter { !$0.isInStock }
            .map(\.requiredName)
        let count = MealPlanViewModel(modelContext: context).addShortfallsToGroceries(for: entries, inventory: inventory)
        guard count > 0 else {
            return .result(value: [], dialog: "You already have everything for your planned meals.")
        }
        let groceries = ((try? context.fetch(FetchDescriptor<GroceryItem>())) ?? [])
            .filter { grocery in missingNames.contains { IngredientNameMatcher.matches($0, grocery.name) } }
            .map(GroceryItemEntity.init(from:))
        return .result(value: groceries, dialog: "Added \(listSentence(missingNames)) to your grocery list.")
    }
}

struct WhatCanICookIntent: AppIntent {
    static let title: LocalizedStringResource = "What Can I Cook"
    static let description = IntentDescription(
        "Finds saved recipes you can make right now with what's in stock.",
        categoryName: "Recipes"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[RecipeEntity]> & ProvidesDialog {
        let context = IntentStore.context
        let inventory = (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []
        let recipes = ((try? context.fetch(FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.name)]))) ?? [])
            .filter { !$0.ingredients.isEmpty }
        let ready = recipes.filter { recipe in
            PantryMatcher().matches(recipeIngredients: recipe.ingredients, inventory: inventory).allSatisfy(\.isInStock)
        }
        guard !ready.isEmpty else {
            return .result(value: [], dialog: "You can't make any saved recipe with what's in stock right now.")
        }
        return .result(
            value: ready.map(RecipeEntity.init(from:)),
            dialog: "You can make \(listSentence(ready.map(\.name)))."
        )
    }
}

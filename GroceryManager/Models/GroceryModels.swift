import Foundation
import SwiftData
import AppIntents

enum QuantityUnit: String, CaseIterable {
    case item = "item"
    case dozen = "dozen"
    case grams = "g"
    case kilograms = "kg"
    case milliliters = "ml"
    case liters = "L"
    case ounces = "oz"
    case pounds = "lb"
    case fluidOunces = "fl oz"
    case teaspoons = "tsp"
    case tablespoons = "tbsp"
    case cups = "cup"
    case pints = "pt"
    case quarts = "qt"
    case gallons = "gal"
    case pinches = "pinch"
    case dashes = "dash"
    case smidgens = "smidgen"
    /// One portion of a prepared meal (batch-cooked food stored as stock).
    case serving = "serving"
}

// CloudKit sync rules for every @Model in this file:
//  • no @Attribute(.unique) — CloudKit can't enforce uniqueness across devices
//  • every stored property has a default value (or is optional)
//  • every relationship is optional
// To-many relationships are stored as optionals and exposed through a non-optional
// computed property, so the rest of the app can keep using `.ingredients` as an array.

@Model
final class StorageLocation {
    var name: String = ""
    var icon: String = "shippingbox"

    @Relationship(deleteRule: .cascade, originalName: "ingredients", inverse: \Ingredient.location)
    var storedIngredients: [Ingredient]? = []

    var ingredients: [Ingredient] {
        get { storedIngredients ?? [] }
        set { storedIngredients = newValue }
    }

    init(name: String, icon: String = "shippingbox") {
        self.name = name
        self.icon = icon
    }
}

@Model
final class Ingredient {
    var name: String = ""
    var quantity: Double = 1
    var unit: String = "item"
    var initialQuantity: Double = 1
    var reorderThreshold: Double = 0
    var category: String = "Other"
    var expiryDate: Date = Date.now
    /// Where the item came from: "manual", "grocery", "prep".
    var source: String = "manual"
    var addedAt: Date = Date.now

    var location: StorageLocation?

    /// Set when this stock row holds portions of a batch-cooked meal.
    @Relationship(inverse: \PrepBatch.stockItem)
    var prepBatch: PrepBatch?

    var isPreparedMeal: Bool { prepBatch != nil || unit == QuantityUnit.serving.rawValue }

    init(
        name: String,
        quantity: Double = 1,
        unit: String = "item",
        initialQuantity: Double? = nil,
        reorderThreshold: Double = 0,
        category: String = "Other",
        expiryDate: Date = .now,
        location: StorageLocation? = nil,
        source: String = "manual"
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.initialQuantity = initialQuantity ?? quantity
        self.reorderThreshold = reorderThreshold
        self.category = category
        self.expiryDate = expiryDate
        self.location = location
        self.source = source
    }
}

@Model
final class Recipe {
    var name: String = ""
    var instructions: String = ""
    /// How many people the ingredient amounts feed. Used to scale planned meals.
    var servings: Int = 2
    var sourceURL: String = ""
    var imageURL: String = ""
    var prepMinutes: Int = 0
    var cookMinutes: Int = 0
    /// Comma-separated free-form tags, e.g. "vegetarian, quick".
    var tags: String = ""
    var createdAt: Date = Date.now
    var isFavorite: Bool = false

    /// Nutrition per serving as declared by the source. Zero means "unknown, estimate it".
    var caloriesPerServing: Double = 0
    var proteinPerServing: Double = 0
    var carbsPerServing: Double = 0
    var fatPerServing: Double = 0

    var tagList: [String] {
        get { tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        set { tags = newValue.joined(separator: ", ") }
    }

    var totalMinutes: Int { prepMinutes + cookMinutes }

    /// Ingredients in the order they were entered. SwiftData doesn't keep relationship order.
    var orderedIngredients: [RecipeIngredient] {
        ingredients.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    @Relationship(deleteRule: .cascade, originalName: "ingredients", inverse: \RecipeIngredient.recipe)
    var storedIngredients: [RecipeIngredient]? = []

    var ingredients: [RecipeIngredient] {
        get { storedIngredients ?? [] }
        set { storedIngredients = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \MealPlanEntry.recipe)
    var mealPlanEntries: [MealPlanEntry]? = []

    @Relationship(deleteRule: .nullify, inverse: \PrepBatch.recipe)
    var prepBatches: [PrepBatch]? = []

    init(name: String, instructions: String = "", servings: Int = 2) {
        self.name = name
        self.instructions = instructions
        self.servings = servings
    }
}

enum MealType: String, CaseIterable, Identifiable, Codable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }

    var sortOrder: Int {
        switch self {
        case .breakfast: 0
        case .lunch: 1
        case .dinner: 2
        case .snack: 3
        }
    }
}

@Model
final class MealPlanEntry {
    /// Start of the planned day (normalised with `Calendar.startOfDay`).
    var date: Date = Date.now
    var mealTypeRaw: String = MealType.dinner.rawValue
    var servings: Int = 2
    var note: String = ""
    var isCooked: Bool = false
    var recipe: Recipe?
    /// Set when this meal is a portion of a batch cooked in a prep session.
    var batch: PrepBatch?
    var isLeftover: Bool { batch != nil }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .dinner }
        set { mealTypeRaw = newValue.rawValue }
    }

    /// Multiplier applied to the recipe's ingredient amounts.
    var scale: Double {
        guard let recipe, recipe.servings > 0 else { return 1 }
        return Double(servings) / Double(recipe.servings)
    }

    init(date: Date, mealType: MealType, recipe: Recipe?, servings: Int, note: String = "") {
        self.date = Calendar.current.startOfDay(for: date)
        self.mealTypeRaw = mealType.rawValue
        self.recipe = recipe
        self.servings = servings
        self.note = note
    }
}

@Model
final class GroceryItem {
    var name: String = ""
    var quantity: Double = 1
    var unit: String = "item"
    /// Store section the item is found in; also the aisle used for sorting.
    var category: String = "Other"
    var isChecked: Bool = false
    /// "manual", "plan" (built from the meal plan) or "lowstock".
    var source: String = "manual"
    /// Start of the week this line was generated for, when `source == "plan"`.
    var plannedWeekStart: Date?
    var note: String = ""
    /// Estimated price in minor units (cents) with its currency; 0 means no estimate.
    var priceCents: Int = 0
    var currencyCode: String = ""
    var storeName: String = ""
    var checkedAt: Date?

    var isManual: Bool { source == "manual" }

    init(name: String, quantity: Double, unit: String, category: String? = nil, source: String = "manual", plannedWeekStart: Date? = nil) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category ?? AisleClassifier.category(for: name)
        self.isChecked = false
        self.source = source
        self.plannedWeekStart = plannedWeekStart
    }
}

@Model
final class RecipeIngredient {
    var name: String = ""
    var requiredQuantity: Double = 1
    var unit: String = "item"
    /// Preparation note such as "diced" or "room temperature".
    var note: String = ""
    var sortOrder: Int = 0
    var recipe: Recipe?

    init(name: String, requiredQuantity: Double = 1, unit: String = "item", note: String = "", sortOrder: Int = 0, recipe: Recipe? = nil) {
        self.name = name
        self.requiredQuantity = requiredQuantity
        self.unit = unit
        self.note = note
        self.sortOrder = sortOrder
        self.recipe = recipe
    }
}


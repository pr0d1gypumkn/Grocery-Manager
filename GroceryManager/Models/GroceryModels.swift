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
}

@Model
final class StorageLocation {
    @Attribute(.unique) var name: String
    var icon: String

    @Relationship(deleteRule: .cascade, inverse: \Ingredient.location)
    var ingredients: [Ingredient] = []

    init(name: String, icon: String = "shippingbox") {
        self.name = name
        self.icon = icon
    }
}

//struct StorageLocationEntity: AppEntity, Sendable {
//    let id: UUID
//    
//    @Property(title: "Add storage location")
//    var title: String
//    
//    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Storage Location"
//    
//    var displayRepresentation: DisplayRepresentation {
//        DisplayRepresentation(title: "\(title)")
//    }
//    
//    static var defaultQuery: StorageLocationEntityQuery()
//        
//        
//}
//
//struct StorageLocationEntityQuery: EntityQuery, Sendable {
//    func entities(for identifiers: [UUID]) async throws -> [StorageLocationEntity] {
//        <#code#>
//    }
//}

@Model
final class Ingredient {
    var name: String
    var quantity: Double
    var unit: String = "item"
    var initialQuantity: Double = 1
    var reorderThreshold: Double = 0
    var category: String
    var expiryDate: Date

    var location: StorageLocation?

    init(
        name: String,
        quantity: Double = 1,
        unit: String = "item",
        initialQuantity: Double? = nil,
        reorderThreshold: Double = 0,
        category: String = "Other",
        expiryDate: Date = .now,
        location: StorageLocation? = nil
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.initialQuantity = initialQuantity ?? quantity
        self.reorderThreshold = reorderThreshold
        self.category = category
        self.expiryDate = expiryDate
        self.location = location
    }
}

@Model
final class Recipe {
    @Attribute(.unique) var name: String
    var instructions: String

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient] = []

    init(name: String, instructions: String = "") {
        self.name = name
        self.instructions = instructions
    }
}

@Model
final class GroceryItem {
    @Attribute(.unique) var name: String
    var quantity: Double
    var unit: String = "item"
    var category: String = "Other"
   
    init(name: String, quantity: Double, unit: String, category: String? = nil) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category ?? "Other"
    }
}

@Model
final class RecipeIngredient {
    var name: String
    var requiredQuantity: Double
    var unit: String = "item"
    var recipe: Recipe?

    init(name: String, requiredQuantity: Double = 1, unit: String = "item", recipe: Recipe? = nil) {
        self.name = name
        self.requiredQuantity = requiredQuantity
        self.unit = unit
        self.recipe = recipe
    }
}


import Foundation

struct PantryMatch: Identifiable, Equatable {
    let id: String
    let requiredName: String
    let requiredQuantity: Double
    let availableQuantity: Double
    let unit: String

    var isInStock: Bool {
        availableQuantity >= requiredQuantity
    }

    var missingQuantity: Double {
        max(requiredQuantity - availableQuantity, 0)
    }
}

struct PantryMatcher {
    func matches(
        recipeIngredients: [RecipeIngredient],
        inventory: [Ingredient],
        now: Date = .now
    ) -> [PantryMatch] {
        return recipeIngredients
            .map { ingredient in
                let availableQuantity = inventory
                    .filter { $0.expiryDate >= now && normalize($0.name) == normalize(ingredient.name) }
                    .reduce(0) { total, inventoryItem in
                        total + (UnitConverter.convert(
                            inventoryItem.quantity,
                            from: inventoryItem.unit,
                            to: ingredient.unit
                        ) ?? 0)
                    }

                return PantryMatch(
                    id: "\(normalize(ingredient.name))-\(ingredient.id)",
                    requiredName: ingredient.name,
                    requiredQuantity: ingredient.requiredQuantity,
                    availableQuantity: availableQuantity,
                    unit: ingredient.unit
                )
            }
    }

    private func normalize(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

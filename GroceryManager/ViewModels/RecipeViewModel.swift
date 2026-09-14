import Foundation
import SwiftData

@MainActor
final class RecipeViewModel: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveRecipe(
        existing existingRecipe: Recipe?,
        name: String,
        instructions: String,
        ingredients: [DraftRecipeIngredient]
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let recipe: Recipe
        if let existing = existingRecipe {
            recipe = existing
        } else {
            recipe = Recipe(name: trimmedName, instructions: instructions)
            modelContext.insert(recipe)
        }
        recipe.name = trimmedName
        recipe.instructions = instructions

        recipe.ingredients.removeAll()
        for draft in ingredients where !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recipe.ingredients.append(RecipeIngredient(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                requiredQuantity: max(draft.quantity, 0),
                unit: draft.unit,
                recipe: recipe
            ))
        }
        saveChanges()
    }

    func delete(_ recipe: Recipe) {
        modelContext.delete(recipe)
        saveChanges()
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Could not save recipe data: \(error)")
        }
    }
}

struct DraftRecipeIngredient: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var quantity: Double
    var unit: String
}

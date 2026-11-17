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
        servings: Int? = nil,
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
        if let servings { recipe.servings = max(servings, 1) }

        // Delete the old rows rather than just detaching them, so orphans don't pile up (and sync).
        recipe.ingredients.forEach(modelContext.delete)
        recipe.ingredients = []
        var order = 0
        for draft in ingredients where !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recipe.ingredients.append(RecipeIngredient(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                requiredQuantity: max(draft.quantity, 0),
                unit: draft.unit,
                note: draft.note,
                sortOrder: order,
                recipe: recipe
            ))
            order += 1
        }
        saveChanges()
    }

    /// Saves an imported recipe with all of its metadata. Returns the saved recipe.
    @discardableResult
    func save(draft: ImportedRecipeDraft, existing: Recipe? = nil) -> Recipe? {
        saveRecipe(existing: existing, name: draft.name, instructions: draft.instructions, servings: draft.servings, ingredients: draft.ingredients)
        let recipe = existing ?? ((try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []).first { $0.name == draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let recipe else { return nil }
        if !draft.sourceURL.isEmpty { recipe.sourceURL = draft.sourceURL }
        if !draft.imageURL.isEmpty { recipe.imageURL = draft.imageURL }
        if draft.prepMinutes > 0 { recipe.prepMinutes = draft.prepMinutes }
        if draft.cookMinutes > 0 { recipe.cookMinutes = draft.cookMinutes }
        if !draft.tags.isEmpty { recipe.tagList = draft.tags }
        if let nutrition = draft.nutritionPerServing {
            recipe.caloriesPerServing = nutrition.calories
            recipe.proteinPerServing = nutrition.protein
            recipe.carbsPerServing = nutrition.carbs
            recipe.fatPerServing = nutrition.fat
        }
        saveChanges()
        return recipe
    }

    func update(_ recipe: Recipe, nutrition: NutritionFacts?, prepMinutes: Int, cookMinutes: Int, tags: [String], sourceURL: String) {
        recipe.caloriesPerServing = nutrition?.calories ?? 0
        recipe.proteinPerServing = nutrition?.protein ?? 0
        recipe.carbsPerServing = nutrition?.carbs ?? 0
        recipe.fatPerServing = nutrition?.fat ?? 0
        recipe.prepMinutes = max(prepMinutes, 0)
        recipe.cookMinutes = max(cookMinutes, 0)
        recipe.tagList = tags
        recipe.sourceURL = sourceURL
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
    var note: String = ""
}

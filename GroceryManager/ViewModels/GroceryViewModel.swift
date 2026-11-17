import Foundation
import SwiftData

@MainActor
final class GroceryViewModel: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveGrocery(
        existing grocery: GroceryItem?,
        name: String,
        quantity: Double,
        unit: String,
        category: String?,
        note: String = ""
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let grocery {
            grocery.name = trimmedName
            grocery.quantity = max(quantity, 0)
            grocery.unit = unit
            grocery.category = category ?? AisleClassifier.category(for: trimmedName)
            grocery.note = note
        } else if let existing = ((try? modelContext.fetch(FetchDescriptor<GroceryItem>())) ?? [])
            .first(where: { IngredientNameMatcher.matches($0.name, trimmedName) && !$0.isChecked }) {
            // Names aren't enforced unique by the store (CloudKit doesn't allow it), so merge here.
            let current = UnitConverter.convert(existing.quantity, from: existing.unit, to: unit) ?? 0
            existing.quantity = max(current, 0) + max(quantity, 0)
            existing.unit = unit
            existing.category = category ?? existing.category
            if !note.isEmpty { existing.note = note }
        } else {
            let item = GroceryItem(name: trimmedName, quantity: max(quantity, 0), unit: unit, category: category)
            item.note = note
            modelContext.insert(item)
        }
        saveChanges()
    }

    // MARK: - Check-off → pantry

    /// Checks an item off and, when enabled, puts it straight into stock at the location its
    /// category belongs in. Unchecking takes it back out so a mis-tap doesn't leave ghosts.
    func setChecked(
        _ grocery: GroceryItem,
        _ checked: Bool,
        inventory: [Ingredient],
        locations: [StorageLocation],
        autoStock: Bool
    ) {
        guard grocery.isChecked != checked else { return }
        grocery.isChecked = checked
        grocery.checkedAt = checked ? .now : nil

        if autoStock {
            let inventoryVM = InventoryViewModel(modelContext: modelContext)
            if checked {
                inventoryVM.restock(
                    name: grocery.name,
                    quantity: grocery.quantity,
                    unit: grocery.unit,
                    category: grocery.category,
                    expiryDate: ShelfLife.defaultExpiry(for: grocery.category),
                    location: ShelfLife.preferredLocation(for: grocery.category, in: locations),
                    existingInventory: inventory,
                    source: "grocery"
                )
            } else {
                _ = inventoryVM.consume(
                    [IngredientRequirement(name: grocery.name, quantity: grocery.quantity, unit: grocery.unit)],
                    from: inventory
                )
            }
        }
        saveChanges()
    }

    func toggleChecked(_ grocery: GroceryItem) {
        grocery.isChecked.toggle()
        grocery.checkedAt = grocery.isChecked ? .now : nil
        saveChanges()
    }

    /// Removes bought items from the list. Their stock was added when they were checked.
    func clearChecked(_ groceries: [GroceryItem]) {
        groceries.filter(\.isChecked).forEach(modelContext.delete)
        saveChanges()
    }

    // MARK: - Adding from recipes and stock

    func addMissingRecipeIngredients(_ ingredients: [RecipeIngredient], inventory: [Ingredient]) {
        let matches = PantryMatcher().matches(recipeIngredients: ingredients, inventory: inventory)
        MealPlanViewModel.addRequirementsToGroceries(matches, modelContext: modelContext)
    }

    func addLowStockIngredients(_ ingredients: [Ingredient]) {
        let existingGroceries = (try? modelContext.fetch(FetchDescriptor<GroceryItem>())) ?? []

        for ingredient in ingredients where !ingredient.isPreparedMeal {
            let threshold = ingredient.reorderThreshold > 0
                ? ingredient.reorderThreshold
                : max(ingredient.initialQuantity, ingredient.quantity) * 0.2

            if ingredient.quantity <= threshold && ingredient.quantity > 0 {
                let neededQuantity = max(ingredient.initialQuantity, ingredient.quantity) - ingredient.quantity
                let existing = existingGroceries.first { IngredientNameMatcher.matches($0.name, ingredient.name) && !$0.isChecked }

                if let existing {
                    let current = UnitConverter.convert(existing.quantity, from: existing.unit, to: ingredient.unit) ?? 0
                    if current < neededQuantity {
                        existing.quantity = neededQuantity
                        existing.unit = ingredient.unit
                    }
                } else {
                    modelContext.insert(GroceryItem(
                        name: ingredient.name,
                        quantity: neededQuantity,
                        unit: ingredient.unit,
                        category: ingredient.category,
                        source: "lowstock"
                    ))
                }
            }
        }
        saveChanges()
    }

    func delete<T: PersistentModel>(_ model: T) {
        modelContext.delete(model)
        saveChanges()
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Could not save grocery data: \(error)")
        }
    }
}

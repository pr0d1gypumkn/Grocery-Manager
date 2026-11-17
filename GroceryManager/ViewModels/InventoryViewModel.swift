import Foundation
import SwiftData

@MainActor
final class InventoryViewModel: ObservableObject {
    enum ExpiryState {
        case fresh
        case soon
        case expired

        var label: String {
            switch self {
            case .fresh: "Fresh"
            case .soon: "Expiring soon"
            case .expired: "Expired"
            }
        }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveLocation(existing location: StorageLocation?, name: String, icon: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let location {
            location.name = trimmedName
            location.icon = icon
        } else if let existing = ((try? modelContext.fetch(FetchDescriptor<StorageLocation>())) ?? [])
            .first(where: { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }) {
            // Names aren't enforced unique by the store (CloudKit doesn't allow it), so do it here.
            existing.icon = icon
        } else {
            modelContext.insert(StorageLocation(name: trimmedName, icon: icon))
        }
        saveChanges()
    }

    func saveIngredient(
        existing ingredient: Ingredient?,
        name: String,
        quantity: Double,
        unit: String,
        initialQuantity: Double,
        reorderThreshold: Double,
        category: String,
        expiryDate: Date,
        location: StorageLocation?
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let ingredient {
            ingredient.name = trimmedName
            ingredient.quantity = max(quantity, 0)
            ingredient.unit = unit
            ingredient.initialQuantity = max(initialQuantity, ingredient.quantity)
            ingredient.reorderThreshold = max(reorderThreshold, 0)
            ingredient.category = category
            ingredient.expiryDate = expiryDate
            ingredient.location = location
        } else {
            modelContext.insert(Ingredient(
                name: trimmedName,
                quantity: max(quantity, 0),
                unit: unit,
                initialQuantity: max(initialQuantity, quantity),
                reorderThreshold: max(reorderThreshold, 0),
                category: category,
                expiryDate: expiryDate,
                location: location
            ))
        }
        saveChanges()
    }

    func delete<T: PersistentModel>(_ model: T) {
        modelContext.delete(model)
        saveChanges()
    }

    func expiryState(for date: Date, now: Date = .now) -> ExpiryState {
        if date < now { return .expired }
        if date <= Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now {
            return .soon
        }
        return .fresh
    }
    
    // MARK: - Stock management

    static func isLowStock(_ ingredient: Ingredient) -> Bool {
        let baseline = max(ingredient.initialQuantity, ingredient.quantity, 0.0001)
        let threshold = ingredient.reorderThreshold > 0 ? ingredient.reorderThreshold : baseline * 0.2
        return ingredient.quantity <= threshold
    }

    /// Nudges stock up or down (e.g. "used one", "bought one more").
    func adjust(_ ingredient: Ingredient, by delta: Double) {
        ingredient.quantity = max(ingredient.quantity + delta, 0)
        if ingredient.quantity > ingredient.initialQuantity {
            ingredient.initialQuantity = ingredient.quantity
        }
        saveChanges()
    }

    /// Resets an item to its full starting amount with a new expiry date.
    func refill(_ ingredient: Ingredient, expiryDate: Date? = nil) {
        ingredient.quantity = max(ingredient.initialQuantity, ingredient.quantity)
        if let expiryDate { ingredient.expiryDate = expiryDate }
        saveChanges()
    }

    /// Deducts requirements from matching stock, using the soonest-expiring items first.
    /// Returns the names of requirements that stock could not fully cover.
    func consume(_ requirements: [IngredientRequirement], from inventory: [Ingredient]) -> [String] {
        var shortfalls: [String] = []

        for requirement in PantryMatcher().merge(requirements) {
            var remaining = requirement.quantity
            let candidates = inventory
                .filter { IngredientNameMatcher.matches($0.name, requirement.name) && $0.quantity > 0 && !$0.isPreparedMeal }
                .sorted { $0.expiryDate < $1.expiryDate }

            for item in candidates where remaining > 0.0001 {
                guard let availableInRequiredUnit = UnitConverter.convert(item.quantity, from: item.unit, to: requirement.unit) else { continue }
                let used = min(availableInRequiredUnit, remaining)
                let usedInItemUnit = UnitConverter.convert(used, from: requirement.unit, to: item.unit) ?? 0
                item.quantity = max(item.quantity - usedInItemUnit, 0)
                remaining -= used
            }

            if remaining > 0.0001 {
                shortfalls.append(requirement.name)
            }
        }
        saveChanges()
        return shortfalls
    }

    /// Adds purchased stock, merging into an existing item with the same name and a compatible unit.
    func restock(
        name: String,
        quantity: Double,
        unit: String,
        category: String,
        expiryDate: Date,
        location: StorageLocation?,
        existingInventory: [Ingredient],
        source: String = "manual"
    ) {
        let quantity = max(quantity, 0)
        if let match = existingInventory.first(where: {
            IngredientNameMatcher.matches($0.name, name)
                && !$0.isPreparedMeal
                && UnitConverter.convert(1, from: unit, to: $0.unit) != nil
                && ($0.location == location || location == nil)
        }) {
            let added = UnitConverter.convert(quantity, from: unit, to: match.unit) ?? 0
            // If the old batch was used up, the new batch's date wins; otherwise keep the
            // sooner date so the older food still triggers an expiry warning.
            match.expiryDate = match.quantity <= 0.0001 ? expiryDate : min(match.expiryDate, expiryDate)
            match.quantity += added
            match.initialQuantity = max(match.initialQuantity, match.quantity)
        } else {
            modelContext.insert(Ingredient(
                name: name,
                quantity: quantity,
                unit: unit,
                initialQuantity: quantity,
                category: category,
                expiryDate: expiryDate,
                location: location,
                source: source
            ))
        }
        saveChanges()
    }

    func checkAndAddLowStockToGroceries(_ ingredients: [Ingredient]) {
        let groceryVM = GroceryViewModel(modelContext: modelContext)
        groceryVM.addLowStockIngredients(ingredients)
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Could not save grocery data: \(error)")
        }
    }
}

import Foundation
import SwiftData

/// One line the meal plan needs the user to buy.
struct PlannedGroceryLine: Equatable, Identifiable {
    var name: String
    var quantity: Double
    var unit: String
    var category: String

    var id: String { "\(IngredientNameMatcher.key(name))|\(unit)" }
}

/// Builds the shopping list from planned meals: merges matching ingredients across recipes,
/// converts units, subtracts what is already in stock, and files each line under an aisle.
struct GroceryListBuilder {
    var matcher = PantryMatcher()

    func lines(for entries: [MealPlanEntry], inventory: [Ingredient], now: Date = .now) -> [PlannedGroceryLine] {
        // Meals eaten from a prep batch don't need raw ingredients again.
        let pending = entries.filter { !$0.isCooked && $0.batch == nil }
        let requirements = MealPlanViewModel.requirements(for: pending)
        return lines(for: requirements, inventory: inventory, now: now)
    }

    func lines(for requirements: [IngredientRequirement], inventory: [Ingredient], now: Date = .now) -> [PlannedGroceryLine] {
        matcher.matches(requirements: requirements, inventory: inventory, now: now)
            .filter { !$0.isInStock }
            .map { match in
                let stockCategory = inventory.first { IngredientNameMatcher.matches($0.name, match.requiredName) }?.category
                return PlannedGroceryLine(
                    name: match.requiredName,
                    quantity: Self.purchaseQuantity(match.missingQuantity, unit: match.unit),
                    unit: match.unit,
                    category: stockCategory ?? AisleClassifier.category(for: match.requiredName)
                )
            }
            .sorted { lhs, rhs in
                let l = AisleClassifier.aisleIndex(for: lhs.category), r = AisleClassifier.aisleIndex(for: rhs.category)
                return l != r ? l < r : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    /// You can't buy 0.37 of an egg; count units round up to whole items.
    static func purchaseQuantity(_ quantity: Double, unit: String) -> Double {
        switch QuantityUnit(rawValue: unit) {
        case .item, .dozen, .serving: quantity.rounded(.up)
        default: (quantity * 100).rounded(.up) / 100
        }
    }

    struct SyncResult: Equatable {
        var added = 0
        var updated = 0
        var removed = 0
        var isEmpty: Bool { added == 0 && updated == 0 && removed == 0 }
    }

    /// Makes the stored grocery list match the plan for one week.
    ///
    /// Plan lines are tagged with `source == "plan"` and the week they belong to, so the
    /// builder can update or remove them when meals change without touching manual items.
    /// Checked lines are left alone until the user clears them.
    @MainActor
    @discardableResult
    func sync(
        weekStart: Date,
        entries: [MealPlanEntry],
        inventory: [Ingredient],
        modelContext: ModelContext,
        now: Date = .now
    ) -> SyncResult {
        let weekStart = Calendar.current.startOfDay(for: weekStart)
        let needed = lines(for: entries, inventory: inventory, now: now)
        let existing = (try? modelContext.fetch(FetchDescriptor<GroceryItem>())) ?? []
        var result = SyncResult()
        var satisfiedKeys: Set<String> = []

        for line in needed {
            let key = IngredientNameMatcher.key(line.name)
            satisfiedKeys.insert(key)
            // Prefer the week's own plan line, then any unchecked line with the same name.
            let candidates = existing.filter { IngredientNameMatcher.key($0.name) == key && !$0.isChecked }
            let match = candidates.first { $0.source == "plan" } ?? candidates.first
            if let match {
                let current = UnitConverter.convert(match.quantity, from: match.unit, to: line.unit)
                if match.source == "plan" {
                    if current != line.quantity || match.unit != line.unit {
                        match.quantity = line.quantity
                        match.unit = line.unit
                        result.updated += 1
                    }
                    match.plannedWeekStart = weekStart
                } else if let current, current < line.quantity {
                    match.quantity = line.quantity
                    match.unit = line.unit
                    result.updated += 1
                }
                if match.category == "Other" { match.category = line.category }
            } else {
                modelContext.insert(GroceryItem(
                    name: line.name,
                    quantity: line.quantity,
                    unit: line.unit,
                    category: line.category,
                    source: "plan",
                    plannedWeekStart: weekStart
                ))
                result.added += 1
            }
        }

        for item in existing where item.source == "plan" && !item.isChecked {
            let sameWeek = item.plannedWeekStart.map { Calendar.current.isDate($0, inSameDayAs: weekStart) } ?? true
            if sameWeek, !satisfiedKeys.contains(IngredientNameMatcher.key(item.name)) {
                modelContext.delete(item)
                result.removed += 1
            }
        }

        if !result.isEmpty {
            try? modelContext.save()
        }
        return result
    }
}

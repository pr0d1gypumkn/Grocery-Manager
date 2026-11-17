import Foundation
import SwiftData

@MainActor
final class MealPlanViewModel: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Planning

    @discardableResult
    func addMeal(recipe: Recipe, on date: Date, mealType: MealType, servings: Int, note: String = "") -> MealPlanEntry {
        let entry = MealPlanEntry(
            date: date,
            mealType: mealType,
            recipe: recipe,
            servings: max(servings, 1),
            note: note
        )
        modelContext.insert(entry)
        saveChanges()
        return entry
    }

    /// Plans one recipe per day, starting on `startDate`, e.g. a meal-prep bundle eaten across the week.
    func addMeals(_ recipes: [Recipe], startingOn startDate: Date, mealType: MealType, servings: Int? = nil) {
        let calendar = Calendar.current
        for (offset, recipe) in recipes.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            modelContext.insert(MealPlanEntry(
                date: day,
                mealType: mealType,
                recipe: recipe,
                servings: max(servings ?? recipe.servings, 1)
            ))
        }
        saveChanges()
    }

    func delete(_ entry: MealPlanEntry) {
        modelContext.delete(entry)
        saveChanges()
    }

    func move(_ entry: MealPlanEntry, to date: Date, mealType: MealType? = nil) {
        entry.date = Calendar.current.startOfDay(for: date)
        if let mealType { entry.mealType = mealType }
        saveChanges()
    }

    /// Duplicates a meal onto another day (and optionally another slot).
    @discardableResult
    func copy(_ entry: MealPlanEntry, to date: Date, mealType: MealType? = nil) -> MealPlanEntry? {
        guard let recipe = entry.recipe else { return nil }
        let copy = MealPlanEntry(date: date, mealType: mealType ?? entry.mealType, recipe: recipe, servings: entry.servings, note: entry.note)
        modelContext.insert(copy)
        saveChanges()
        return copy
    }

    /// Repeats a meal on the same weekday for the next `weeks` weeks.
    func repeatWeekly(_ entry: MealPlanEntry, weeks: Int) {
        let calendar = Calendar.current
        for offset in 1...max(weeks, 1) {
            guard let day = calendar.date(byAdding: .weekOfYear, value: offset, to: entry.date), let recipe = entry.recipe else { continue }
            modelContext.insert(MealPlanEntry(date: day, mealType: entry.mealType, recipe: recipe, servings: entry.servings, note: entry.note))
        }
        saveChanges()
    }

    /// Copies every meal from one week into another, skipping slots that already hold the same recipe.
    @discardableResult
    func copyWeek(from sourceWeekStart: Date, to targetWeekStart: Date, allEntries: [MealPlanEntry]) -> Int {
        let calendar = Calendar.current
        let source = calendar.startOfDay(for: sourceWeekStart)
        let target = calendar.startOfDay(for: targetWeekStart)
        guard let sourceEnd = calendar.date(byAdding: .day, value: 7, to: source) else { return 0 }
        let sourceEntries = allEntries.filter { $0.date >= source && $0.date < sourceEnd }
        var copied = 0
        for entry in sourceEntries {
            guard let recipe = entry.recipe else { continue }
            let dayOffset = calendar.dateComponents([.day], from: source, to: entry.date).day ?? 0
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: target) else { continue }
            let duplicate = allEntries.contains { $0.date == day && $0.mealType == entry.mealType && $0.recipe === recipe }
            guard !duplicate else { continue }
            modelContext.insert(MealPlanEntry(date: day, mealType: entry.mealType, recipe: recipe, servings: entry.servings, note: entry.note))
            copied += 1
        }
        saveChanges()
        return copied
    }

    // MARK: - Stock

    /// The scaled ingredient amounts a set of planned meals will use.
    nonisolated static func requirements(for entries: [MealPlanEntry]) -> [IngredientRequirement] {
        entries.flatMap { entry -> [IngredientRequirement] in
            guard let recipe = entry.recipe else { return [] }
            return recipe.ingredients.map {
                IngredientRequirement(name: $0.name, quantity: $0.requiredQuantity * entry.scale, unit: $0.unit)
            }
        }
    }

    /// Marks a meal as cooked and deducts its ingredients from stock. Meals served from a
    /// prep batch take portions from the batch instead of raw ingredients.
    /// Returns the names of ingredients that were not fully in stock.
    @discardableResult
    func markCooked(_ entry: MealPlanEntry, inventory: [Ingredient]) -> [String] {
        guard !entry.isCooked else { return [] }
        var shortfalls: [String] = []
        if let batch = entry.batch {
            eat(portions: entry.servings, from: batch)
        } else {
            shortfalls = InventoryViewModel(modelContext: modelContext)
                .consume(Self.requirements(for: [entry]), from: inventory)
        }
        entry.isCooked = true
        saveChanges()
        return shortfalls
    }

    /// Undo for `markCooked`. Does not put ingredients back, since the food was probably eaten.
    func markNotCooked(_ entry: MealPlanEntry) {
        entry.isCooked = false
        saveChanges()
    }

    /// Adds everything the given meals need but stock can't cover to the grocery list.
    /// Returns how many grocery lines were added or topped up.
    @discardableResult
    func addShortfallsToGroceries(for entries: [MealPlanEntry], inventory: [Ingredient]) -> Int {
        let missing = PantryMatcher()
            .matches(requirements: Self.requirements(for: entries.filter { !$0.isCooked && $0.batch == nil }), inventory: inventory)
            .filter { !$0.isInStock }
        return Self.addRequirementsToGroceries(missing, modelContext: modelContext)
    }

    /// Adds the missing part of each match to the grocery list, topping up existing lines
    /// rather than duplicating them. Returns how many matches were added or topped up.
    @discardableResult
    static func addRequirementsToGroceries(_ matches: [PantryMatch], modelContext: ModelContext) -> Int {
        let missing = matches.filter { !$0.isInStock }
        guard !missing.isEmpty else { return 0 }

        let existing = (try? modelContext.fetch(FetchDescriptor<GroceryItem>())) ?? []
        for match in missing {
            let quantity = GroceryListBuilder.purchaseQuantity(match.missingQuantity, unit: match.unit)
            if let grocery = existing.first(where: { IngredientNameMatcher.matches($0.name, match.requiredName) && !$0.isChecked }) {
                let current = UnitConverter.convert(grocery.quantity, from: grocery.unit, to: match.unit) ?? 0
                if current < quantity {
                    grocery.quantity = quantity
                    grocery.unit = match.unit
                }
            } else {
                modelContext.insert(GroceryItem(name: match.requiredName, quantity: quantity, unit: match.unit))
            }
        }
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Could not save groceries: \(error)")
        }
        return missing.count
    }

    // MARK: - Prep sessions

    struct BatchSpec {
        var recipe: Recipe
        var portions: Int
        var container: String
        var storage: BatchStorage
    }

    /// Finishes a prep session: raw ingredients come out of stock once for every recipe,
    /// each recipe becomes a batch of portions stored as stock, and the week's meals for that
    /// recipe are pointed at the batch so eating them takes a portion, not ingredients again.
    @discardableResult
    func completePrepSession(
        _ session: PrepSession,
        specs: [BatchSpec],
        entries: [MealPlanEntry],
        inventory: [Ingredient],
        locations: [StorageLocation]
    ) -> [String] {
        let covered = entries.filter { entry in
            !entry.isCooked && entry.batch == nil && specs.contains { $0.recipe === entry.recipe }
        }
        let shortfalls = InventoryViewModel(modelContext: modelContext)
            .consume(Self.requirements(for: covered), from: inventory)

        for spec in specs where spec.portions > 0 {
            let batch = PrepBatch(name: spec.recipe.name, portions: spec.portions, container: spec.container, storage: spec.storage, recipe: spec.recipe)
            batch.session = session
            modelContext.insert(batch)

            let stock = Ingredient(
                name: "\(spec.recipe.name) (prepped)",
                quantity: Double(spec.portions),
                unit: QuantityUnit.serving.rawValue,
                category: "Prepared",
                expiryDate: batch.expiryDate,
                location: locations.first { $0.name.localizedCaseInsensitiveContains(spec.storage.rawValue) } ?? locations.first,
                source: "prep"
            )
            stock.prepBatch = batch
            modelContext.insert(stock)
            batch.stockItem = stock

            for entry in covered where entry.recipe === spec.recipe {
                entry.batch = batch
            }
        }
        session.isCompleted = true
        saveChanges()
        return shortfalls
    }

    /// Takes portions out of a batch (and its stock row).
    func eat(portions: Int, from batch: PrepBatch) {
        let taken = min(max(portions, 0), batch.portionsLeft)
        batch.portionsLeft -= taken
        if let stock = batch.stockItem {
            stock.quantity = max(stock.quantity - Double(taken), 0)
            if stock.quantity <= 0 {
                modelContext.delete(stock)
                batch.stockItem = nil
            }
        }
        saveChanges()
    }

    /// Portions in the batch that no planned meal is going to eat.
    static func unscheduledPortions(of batch: PrepBatch) -> Int {
        let planned = batch.meals.filter { !$0.isCooked }.reduce(0) { $0 + $1.servings }
        return max(batch.portionsLeft - planned, 0)
    }

    /// Fills upcoming empty slots with leftovers until the batch is spoken for or expires.
    @discardableResult
    func scheduleLeftovers(
        from batch: PrepBatch,
        startingAfter date: Date,
        mealType: MealType,
        servingsPerMeal: Int,
        allEntries: [MealPlanEntry]
    ) -> Int {
        guard let recipe = batch.recipe else { return 0 }
        let calendar = Calendar.current
        var remaining = Self.unscheduledPortions(of: batch)
        var day = calendar.startOfDay(for: date)
        var scheduled = 0
        let perMeal = max(servingsPerMeal, 1)
        while remaining > 0 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            if day > batch.expiryDate { break }
            let occupied = allEntries.contains { $0.date == day && $0.mealType == mealType }
            guard !occupied else { continue }
            let servings = min(perMeal, remaining)
            let entry = MealPlanEntry(date: day, mealType: mealType, recipe: recipe, servings: servings, note: "Leftovers")
            entry.batch = batch
            modelContext.insert(entry)
            remaining -= servings
            scheduled += 1
        }
        saveChanges()
        return scheduled
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Could not save meal plan: \(error)")
        }
    }
}

extension Date {
    /// The seven days of the week containing `self`, starting on the locale's first weekday.
    var weekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: self)?.start ?? calendar.startOfDay(for: self)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var weekStart: Date {
        weekDays.first ?? Calendar.current.startOfDay(for: self)
    }
}

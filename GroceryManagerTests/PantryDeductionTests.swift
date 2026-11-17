import SwiftData
import XCTest
@testable import GroceryManager

@MainActor
final class PantryDeductionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try PersistenceController.makeInMemoryContainer()
    }

    private func stock(_ name: String, _ quantity: Double, _ unit: String, expiresIn days: Int = 10) -> Ingredient {
        let item = Ingredient(name: name, quantity: quantity, unit: unit, expiryDate: Date.now.addingTimeInterval(Double(days) * 86_400))
        context.insert(item)
        return item
    }

    func testConsumeUsesSoonestExpiringFirstAndConvertsUnits() {
        let old = stock("Milk", 1, "cup", expiresIn: 1)
        let fresh = stock("Milk", 1, "L", expiresIn: 7)

        let shortfalls = InventoryViewModel(modelContext: context)
            .consume([IngredientRequirement(name: "milk", quantity: 500, unit: "ml")], from: [fresh, old])

        XCTAssertTrue(shortfalls.isEmpty)
        XCTAssertEqual(old.quantity, 0, accuracy: 0.0001, "the older carton goes first")
        XCTAssertEqual(fresh.quantity, 1 - (500 - 236.5882365) / 1000, accuracy: 0.0001)
    }

    func testConsumeReportsShortfalls() {
        let eggs = stock("Eggs", 2, "item")
        let shortfalls = InventoryViewModel(modelContext: context)
            .consume([IngredientRequirement(name: "eggs", quantity: 3, unit: "item")], from: [eggs])
        XCTAssertEqual(shortfalls, ["eggs"])
        XCTAssertEqual(eggs.quantity, 0)
    }

    func testCookingAMealDeductsScaledIngredients() {
        let rice = stock("Rice", 1000, "g")
        let recipe = Recipe(name: "Rice bowl", servings: 2)
        context.insert(recipe)
        recipe.ingredients.append(RecipeIngredient(name: "rice", requiredQuantity: 200, unit: "g", recipe: recipe))
        let viewModel = MealPlanViewModel(modelContext: context)
        let entry = viewModel.addMeal(recipe: recipe, on: .now, mealType: .dinner, servings: 4)

        let shortfalls = viewModel.markCooked(entry, inventory: [rice])

        XCTAssertTrue(shortfalls.isEmpty)
        XCTAssertTrue(entry.isCooked)
        XCTAssertEqual(rice.quantity, 600, "4 servings of a 2-serving recipe doubles the amount")
    }

    func testCheckingOffGroceryAddsStockAndUncheckingRemovesIt() {
        let fridge = StorageLocation(name: "Fridge")
        context.insert(fridge)
        let grocery = GroceryItem(name: "Greek yogurt", quantity: 500, unit: "g", category: "Dairy")
        context.insert(grocery)
        let viewModel = GroceryViewModel(modelContext: context)

        viewModel.setChecked(grocery, true, inventory: [], locations: [fridge], autoStock: true)
        var inventory = try! context.fetch(FetchDescriptor<Ingredient>())
        XCTAssertEqual(inventory.count, 1)
        XCTAssertEqual(inventory.first?.quantity, 500)
        XCTAssertEqual(inventory.first?.location?.name, "Fridge")
        XCTAssertEqual(inventory.first?.source, "grocery")

        viewModel.setChecked(grocery, false, inventory: inventory, locations: [fridge], autoStock: true)
        inventory = try! context.fetch(FetchDescriptor<Ingredient>())
        XCTAssertEqual(inventory.first?.quantity, 0)
    }

    func testPrepSessionMovesIngredientsIntoPortionsAndLeftoversEatPortions() {
        let chicken = stock("Chicken thighs", 1000, "g")
        let fridge = StorageLocation(name: "Fridge")
        context.insert(fridge)
        let recipe = Recipe(name: "Chicken bowls", servings: 2)
        context.insert(recipe)
        recipe.ingredients.append(RecipeIngredient(name: "chicken thighs", requiredQuantity: 400, unit: "g", recipe: recipe))
        let viewModel = MealPlanViewModel(modelContext: context)
        let monday = viewModel.addMeal(recipe: recipe, on: .now, mealType: .dinner, servings: 2)
        let session = PrepSession(weekStart: .now, title: "Test", plan: PrepPlan(steps: [], recipes: [], estimatedMinutes: 0))
        context.insert(session)

        viewModel.completePrepSession(
            session,
            specs: [.init(recipe: recipe, portions: 4, container: "2 boxes", storage: .fridge)],
            entries: [monday],
            inventory: [chicken],
            locations: [fridge]
        )

        XCTAssertEqual(chicken.quantity, 600, "raw ingredients leave stock once, for the planned servings")
        let batch = try! XCTUnwrap(session.batches.first)
        XCTAssertEqual(batch.portionsLeft, 4)
        XCTAssertNotNil(monday.batch)
        let prepped = try! XCTUnwrap(batch.stockItem)
        XCTAssertEqual(prepped.quantity, 4)
        XCTAssertEqual(prepped.unit, "serving")

        let scheduled = viewModel.scheduleLeftovers(from: batch, startingAfter: .now, mealType: .lunch, servingsPerMeal: 1, allEntries: [monday])
        XCTAssertEqual(scheduled, 2, "two portions beyond Monday's dinner become two lunches")

        viewModel.markCooked(monday, inventory: [chicken])
        XCTAssertEqual(chicken.quantity, 600, "eating from a batch does not touch raw stock again")
        XCTAssertEqual(batch.portionsLeft, 2)
        XCTAssertEqual(prepped.quantity, 2)
    }

    func testGroceryListSyncTracksPlanChanges() {
        let recipe = Recipe(name: "Omelette", servings: 1)
        context.insert(recipe)
        recipe.ingredients.append(RecipeIngredient(name: "eggs", requiredQuantity: 3, unit: "item", recipe: recipe))
        recipe.ingredients.append(RecipeIngredient(name: "cheddar", requiredQuantity: 30, unit: "g", recipe: recipe))
        let cheddar = stock("Cheddar", 200, "g")
        let viewModel = MealPlanViewModel(modelContext: context)
        let weekStart = Date.now.weekStart
        let entry = viewModel.addMeal(recipe: recipe, on: weekStart, mealType: .breakfast, servings: 2)

        var result = GroceryListBuilder().sync(weekStart: weekStart, entries: [entry], inventory: [cheddar], modelContext: context)
        XCTAssertEqual(result, GroceryListBuilder.SyncResult(added: 1, updated: 0, removed: 0))
        var groceries = try! context.fetch(FetchDescriptor<GroceryItem>())
        XCTAssertEqual(groceries.first?.name, "eggs")
        XCTAssertEqual(groceries.first?.quantity, 6)
        XCTAssertEqual(groceries.first?.source, "plan")

        entry.servings = 1
        result = GroceryListBuilder().sync(weekStart: weekStart, entries: [entry], inventory: [cheddar], modelContext: context)
        XCTAssertEqual(result.updated, 1)
        groceries = try! context.fetch(FetchDescriptor<GroceryItem>())
        XCTAssertEqual(groceries.first?.quantity, 3)

        result = GroceryListBuilder().sync(weekStart: weekStart, entries: [], inventory: [cheddar], modelContext: context)
        XCTAssertEqual(result.removed, 1)
        XCTAssertTrue(try! context.fetch(FetchDescriptor<GroceryItem>()).isEmpty)
    }
}

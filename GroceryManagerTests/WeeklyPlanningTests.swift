import SwiftData
import XCTest
@testable import GroceryManager

@MainActor
final class WeeklyPlanningTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try PersistenceController.makeInMemoryContainer()
    }

    private func recipe(_ name: String, _ ingredients: [(String, Double, String)], servings: Int = 2) -> Recipe {
        let recipe = Recipe(name: name, servings: servings)
        context.insert(recipe)
        for (index, item) in ingredients.enumerated() {
            recipe.ingredients.append(RecipeIngredient(name: item.0, requiredQuantity: item.1, unit: item.2, sortOrder: index, recipe: recipe))
        }
        return recipe
    }

    private func recipes(_ count: Int) -> [Recipe] {
        (0..<count).map { recipe("Recipe \($0)", [("ingredient \($0)", 100, "g")]) }
    }

    private func options(locked: [(dayOffset: Int, mealType: MealType, recipe: Recipe)] = []) -> AutoPlanner.Options {
        AutoPlanner.Options(servingsPerMeal: 2, dietTags: [], pantry: [], prices: nil, weeklyBudgetCents: 0, locked: locked)
    }

    // MARK: - Auto planner

    func testPlanFillsEverySlotWhenThereAreFewerRecipesThanSlots() {
        let proposals = AutoPlanner().plan(recipes: recipes(4), options: options())
        XCTAssertEqual(proposals.count, AutoPlanner.defaultSlots.count, "every slot gets a meal, repeating once all recipes are used")
    }

    func testSlotBySlotPlanningFillsEverySlot() {
        // "Plan my week" plans one slot at a time so a swap only changes that slot.
        let all = recipes(4)
        var results: [AutoPlanner.Proposal] = []
        for slot in AutoPlanner.defaultSlots {
            let locked = results.map { (dayOffset: $0.dayOffset, mealType: $0.mealType, recipe: $0.recipe) }
            results += AutoPlanner().plan(recipes: all, slots: [slot], options: options(locked: locked))
        }
        XCTAssertEqual(results.count, AutoPlanner.defaultSlots.count)
    }

    func testPlanDoesNotRepeatUntilEveryRecipeIsUsed() {
        let all = recipes(12)
        let proposals = AutoPlanner().plan(recipes: all, options: options())
        XCTAssertEqual(Set(proposals.map(\.recipe.name)).count, proposals.count)
    }

    func testRepeatsAvoidTheNextDay() {
        let all = recipes(2)
        let slots = (0..<4).map { AutoPlanner.Slot(dayOffset: $0, mealType: .dinner) }
        let names = AutoPlanner().plan(recipes: all, slots: slots, options: options()).map(\.recipe.name)
        XCTAssertEqual(names.count, 4)
        for (a, b) in zip(names, names.dropFirst()) {
            XCTAssertNotEqual(a, b, "the same recipe isn't planned two days running when another is free")
        }
    }

    func testAlternativesExcludeTheCurrentRecipeAndAreRanked() {
        let pantry = [Ingredient(name: "Rice", quantity: 1000, unit: "g")]
        pantry.forEach(context.insert)
        let stocked = recipe("Rice bowl", [("rice", 200, "g")])
        let current = recipe("Pasta", [("pasta", 200, "g")])
        _ = recipe("Soup", [("leek", 2, "item")])
        var opts = options()
        opts.pantry = pantry
        opts.excludeRecipeNames = [current.name]

        let alternatives = AutoPlanner().alternatives(for: .init(dayOffset: 0, mealType: .dinner), recipes: [stocked, current] + [], options: opts)
        XCTAssertFalse(alternatives.contains { $0.recipe.name == "Pasta" })
        XCTAssertEqual(alternatives.first?.recipe.name, "Rice bowl", "the recipe you can make from the pantry ranks first")
    }

    // MARK: - Leftovers

    func testPlannedLeftoversAddServingsToTheSourceAndNeedNoIngredients() throws {
        let chili = recipe("Chili", [("beans", 400, "g")], servings: 2)
        let viewModel = MealPlanViewModel(modelContext: context)
        let monday = Calendar.current.startOfDay(for: .now)
        let dinner = viewModel.addMeal(recipe: chili, on: monday, mealType: .dinner, servings: 2)

        let leftovers = try XCTUnwrap(viewModel.planLeftovers(of: dinner, extraServings: 2))

        XCTAssertEqual(dinner.servings, 4)
        XCTAssertEqual(dinner.servingsEaten, 2)
        XCTAssertEqual(leftovers.mealType, .lunch)
        XCTAssertEqual(leftovers.date, Calendar.current.date(byAdding: .day, value: 1, to: monday))
        XCTAssertTrue(leftovers.isLeftover)
        let needs = MealPlanViewModel.requirements(for: [dinner, leftovers])
        XCTAssertEqual(needs.count, 1, "only the dinner needs ingredients")
        XCTAssertEqual(needs.first?.quantity ?? 0, 800, accuracy: 0.001, "scaled for 4 servings")
    }

    func testEatingLeftoversDoesNotTouchStock() throws {
        let beans = Ingredient(name: "Beans", quantity: 1000, unit: "g")
        context.insert(beans)
        let chili = recipe("Chili", [("beans", 400, "g")], servings: 2)
        let viewModel = MealPlanViewModel(modelContext: context)
        let dinner = viewModel.addMeal(recipe: chili, on: .now, mealType: .dinner, servings: 2)
        let leftovers = try XCTUnwrap(viewModel.planLeftovers(of: dinner, extraServings: 2))

        viewModel.markCooked(dinner, inventory: [beans])
        XCTAssertEqual(beans.quantity, 200, accuracy: 0.001)
        viewModel.markCooked(leftovers, inventory: [beans])
        XCTAssertEqual(beans.quantity, 200, accuracy: 0.001)
        XCTAssertTrue(leftovers.isCooked)
    }

    func testRemovingLeftoversGivesTheServingsBack() throws {
        let chili = recipe("Chili", [("beans", 400, "g")])
        let viewModel = MealPlanViewModel(modelContext: context)
        let dinner = viewModel.addMeal(recipe: chili, on: .now, mealType: .dinner, servings: 2)
        let leftovers = try XCTUnwrap(viewModel.planLeftovers(of: dinner, extraServings: 3))

        viewModel.delete(leftovers)
        XCTAssertEqual(dinner.servings, 2)
    }

    func testRemovingTheSourceRemovesItsLeftovers() throws {
        let chili = recipe("Chili", [("beans", 400, "g")])
        let viewModel = MealPlanViewModel(modelContext: context)
        let dinner = viewModel.addMeal(recipe: chili, on: .now, mealType: .dinner, servings: 2)
        viewModel.planLeftovers(of: dinner, extraServings: 2)

        viewModel.delete(dinner)
        let remaining = try context.fetch(FetchDescriptor<MealPlanEntry>())
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSwappingARecipeCarriesItsLeftovers() throws {
        let chili = recipe("Chili", [("beans", 400, "g")])
        let curry = recipe("Curry", [("chickpeas", 400, "g")])
        let viewModel = MealPlanViewModel(modelContext: context)
        let dinner = viewModel.addMeal(recipe: chili, on: .now, mealType: .dinner, servings: 2)
        let leftovers = try XCTUnwrap(viewModel.planLeftovers(of: dinner, extraServings: 2))

        viewModel.swapRecipe(of: dinner, to: curry)
        XCTAssertTrue(dinner.recipe === curry)
        XCTAssertTrue(leftovers.recipe === curry)
    }

    func testGroceryListCountsLeftoversOnce() throws {
        let chili = recipe("Chili", [("beans", 400, "g")], servings: 2)
        let viewModel = MealPlanViewModel(modelContext: context)
        let dinner = viewModel.addMeal(recipe: chili, on: .now, mealType: .dinner, servings: 2)
        let leftovers = try XCTUnwrap(viewModel.planLeftovers(of: dinner, extraServings: 2))

        let lines = GroceryListBuilder().lines(for: [dinner, leftovers], inventory: [])
        XCTAssertEqual(lines.count, 1)
    }
}

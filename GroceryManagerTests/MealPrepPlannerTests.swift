import XCTest
@testable import GroceryManager

final class MealPrepPlannerTests: XCTestCase {
    private struct TestRecipe {
        let name: String
        let ingredients: [String]
        var instructions: String = ""
    }

    private func planner(_ recipes: [TestRecipe]) -> MealPrepPlanner<TestRecipe> {
        MealPrepPlanner(
            items: recipes,
            name: \.name,
            ingredientNames: \.ingredients,
            instructions: \.instructions
        )
    }

    // MARK: Food groups

    func testClassifiesCommonIngredients() {
        XCTAssertEqual(FoodGroup.classify("Chicken thighs"), .protein)
        XCTAssertEqual(FoodGroup.classify("brown rice"), .grains)
        XCTAssertEqual(FoodGroup.classify("Chickpeas"), .legumes)
        XCTAssertEqual(FoodGroup.classify("Greek yogurt"), .dairy)
        XCTAssertEqual(FoodGroup.classify("Blueberries"), .fruit)
        XCTAssertEqual(FoodGroup.classify("diced onion"), .vegetables)
    }

    func testLongerPhraseWins() {
        XCTAssertEqual(FoodGroup.classify("green beans"), .vegetables)
        XCTAssertEqual(FoodGroup.classify("black beans"), .legumes)
    }

    func testStaplesAreIgnored() {
        XCTAssertNil(FoodGroup.classify("Olive oil"))
        XCTAssertNil(FoodGroup.classify("salt"))
        XCTAssertNil(FoodGroup.classify("black pepper"))
        XCTAssertTrue(PrepStaples.isStaple("Kosher salt"))
    }

    // MARK: Techniques

    func testDetectsTechniquesAndOvenTemperature() {
        let text = "Preheat the oven to 400°F. Roast the vegetables. Boil the pasta."
        XCTAssertEqual(PrepTechnique.detect(in: text), [.oven, .boil])
        XCTAssertEqual(PrepTechnique.ovenTemperatures(in: text), ["400°F"])
    }

    func testDutchOvenIsNotTheOven() {
        XCTAssertFalse(PrepTechnique.detect(in: "Simmer in a Dutch oven for an hour.").contains(.oven))
    }

    // MARK: Bundles

    func testBundlesPreferSharedIngredientsAndVariety() {
        let recipes = [
            TestRecipe(name: "Chicken rice bowl", ingredients: ["chicken", "rice", "broccoli", "onion"],
                       instructions: "Dice the onion. Roast broccoli at 425°F."),
            TestRecipe(name: "Chickpea curry", ingredients: ["chickpeas", "rice", "onion", "spinach", "yogurt"],
                       instructions: "Dice the onion and simmer."),
            TestRecipe(name: "Fruit salad", ingredients: ["apple", "banana", "mint"]),
            TestRecipe(name: "Sheet pan salmon", ingredients: ["salmon", "broccoli", "lemon"],
                       instructions: "Roast at 425°F for 15 minutes.")
        ]

        let bundles = planner(recipes).bundles(size: 2)
        let best = try! XCTUnwrap(bundles.first)

        XCTAssertFalse(best.items.contains { $0.name == "Fruit salad" }, "Fruit salad shares nothing")
        XCTAssertFalse(best.sharedIngredients.isEmpty)
        XCTAssertGreaterThan(best.totalIngredientCount, best.uniqueIngredientCount)
        XCTAssertFalse(bundles.contains { $0.items.contains { $0.name == "Fruit salad" } })
    }

    func testBundleTasksCoverSharedPrep() {
        let recipes = [
            TestRecipe(name: "A", ingredients: ["chicken breast", "onion", "quinoa"],
                       instructions: "Dice the onion. Bake at 400°F."),
            TestRecipe(name: "B", ingredients: ["quinoa", "onion", "black beans"],
                       instructions: "Dice the onion. Roast peppers in the oven at 400°F.")
        ]

        let bundle = try! XCTUnwrap(planner(recipes).bundles(size: 2).first)
        let titles = bundle.tasks.map(\.title)

        XCTAssertTrue(titles.contains { $0.contains("quinoa") && $0.contains("batch") }, "\(titles)")
        XCTAssertTrue(titles.contains { $0.hasPrefix("Dice") && $0.contains("onion") }, "\(titles)")
        XCTAssertTrue(titles.contains("Share one oven session at 400°F"), "\(titles)")
    }

    func testAnchoredBundlesIncludeAnchor() {
        let recipes = [
            TestRecipe(name: "A", ingredients: ["rice", "tofu"]),
            TestRecipe(name: "B", ingredients: ["rice", "egg"]),
            TestRecipe(name: "C", ingredients: ["egg", "spinach"])
        ]

        let bundles = planner(recipes).bundles(size: 2, anchor: { $0.name == "C" })

        XCTAssertFalse(bundles.isEmpty)
        XCTAssertTrue(bundles.allSatisfy { $0.items.contains { $0.name == "C" } })
    }

    func testNearDuplicatesArePenalised() {
        let recipes = [
            TestRecipe(name: "Pasta 1", ingredients: ["pasta", "tomato", "garlic", "basil"]),
            TestRecipe(name: "Pasta 2", ingredients: ["pasta", "tomato", "garlic", "basil"]),
            TestRecipe(name: "Lentil soup", ingredients: ["lentils", "tomato", "garlic", "carrot"])
        ]

        let companions = planner(recipes).companions(for: { $0.name == "Pasta 1" })

        XCTAssertEqual(companions.first?.item.name, "Lentil soup")
        XCTAssertTrue(companions.first?.addedGroups.contains(.legumes) == true)
    }

    func testRecipesWithNothingInCommonGetNoCompanions() {
        let recipes = [
            TestRecipe(name: "A", ingredients: ["chicken"]),
            TestRecipe(name: "B", ingredients: ["banana"])
        ]

        XCTAssertTrue(planner(recipes).companions(for: { $0.name == "A" }).isEmpty)
        XCTAssertTrue(planner(recipes).bundles(size: 2).isEmpty)
    }
}

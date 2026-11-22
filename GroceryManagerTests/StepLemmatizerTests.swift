import XCTest
import SwiftData
@testable import GroceryManager

final class StepLemmatizerTests: XCTestCase {
    func testOperationsAreLemmatised() {
        XCTAssertEqual(StepLemmatizer.operations(in: "Chop the onions and mince the garlic."), ["chop", "mince"])
        XCTAssertEqual(StepLemmatizer.operations(in: "Keep stirring while the sauce is simmering."), ["stir", "simmer"])
        XCTAssertEqual(StepLemmatizer.operations(in: "Stir-fried the beef until browned, about 5 minutes."), ["stir-fry", "brown"])
        XCTAssertEqual(StepLemmatizer.operations(in: "Sautéing the peppers, then slicing them thinly."), ["saute", "slice"])
        XCTAssertEqual(StepLemmatizer.operations(in: "Pat dry the chicken, then season with salt."), ["pat dry", "season"])
        XCTAssertEqual(StepLemmatizer.operations(in: "Preheat the oven and bake for 20 minutes."), ["preheat", "bake"])
    }

    func testDescriptiveWordsAreNotOperations() {
        XCTAssertEqual(StepLemmatizer.operations(in: "Line a baking sheet with paper."), [])
        XCTAssertEqual(StepLemmatizer.operations(in: "Add the chopped onion and cooked rice."), ["add"])
        XCTAssertEqual(StepLemmatizer.operations(in: "Remove from the heat and stir in the brown sugar."), ["stir"])
        XCTAssertEqual(StepLemmatizer.operations(in: "Toss with the dressing."), ["toss"])
    }

    func testIngredientsInStepUseLemmaKeys() {
        let keys = ["onion", "chicken thigh", "garlic", "olive oil"].map(IngredientNameMatcher.key)
        XCTAssertEqual(StepLemmatizer.ingredients(in: "Dice the onions.", keys: keys), ["onion"])
        XCTAssertEqual(StepLemmatizer.ingredients(in: "Sear the chicken in the oil.", keys: keys), ["chicken thigh", "olive oil"])
    }

    func testDifferentWordingOverlaps() {
        let keys = ["onion"]
        let first = StepLemmatizer.steps(from: "Dice the onion.", ingredientKeys: keys)[0]
        let second = StepLemmatizer.steps(from: "Finely chopping 2 onions", ingredientKeys: keys)[0]
        let third = StepLemmatizer.steps(from: "Sauté the onion.", ingredientKeys: keys)[0]
        XCTAssertTrue(first.overlaps(second))
        XCTAssertFalse(first.overlaps(third))
    }

    @MainActor
    func testLemmasAreStoredOnSave() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        LemmaIndexer.install(on: container)
        let context = container.mainContext

        let recipe = Recipe(name: "Soup", instructions: "Chop the carrots.\nSimmer for 20 minutes.")
        context.insert(recipe)
        let carrot = RecipeIngredient(name: "Diced Carrots", recipe: recipe)
        recipe.ingredients.append(carrot)
        let stock = Ingredient(name: "Fresh Tomatoes")
        context.insert(stock)
        try context.save()

        XCTAssertEqual(carrot.lemmaName, "carrot")
        XCTAssertEqual(stock.lemmaName, "tomato")
        let stored = try JSONDecoder().decode([RecipeStep].self, from: recipe.stepsJSON)
        XCTAssertEqual(stored.map(\.operations), [["chop"], ["simmer"]])
        XCTAssertEqual(stored[0].ingredients, ["carrot"])

        stock.name = "Cherry tomatoes"
        recipe.instructions = "Grate the carrots."
        try context.save()
        XCTAssertEqual(stock.lemmaName, "cherry tomato")
        XCTAssertEqual(recipe.lemmatizedSteps.map(\.operations), [["grate"]])
    }

    func testPlannerMergesDifferentlyWordedKnifeWork() {
        let plan = PrepSessionPlanner().plan([
            PrepRecipeInput(name: "A", instructions: "Finely chop the onions.\nSimmer for 10 minutes.", ingredientNames: ["onion"], servings: 2),
            PrepRecipeInput(name: "B", instructions: "Chop onion and slice the peppers.\nBake for 20 minutes.", ingredientNames: ["onions", "bell pepper"], servings: 2)
        ])
        let titles = plan.steps.map(\.title)
        XCTAssertTrue(titles.contains { $0.hasPrefix("Chop onion") }, "\(titles)")
        XCTAssertFalse(titles.contains("Finely chop the onions."), "covered by the shared step: \(titles)")
        XCTAssertTrue(titles.contains("Chop onion and slice the peppers."), "peppers still need slicing: \(titles)")
    }
}

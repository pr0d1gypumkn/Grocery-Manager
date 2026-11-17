import SwiftData
import XCTest
@testable import GroceryManager

@MainActor
final class PlusFeatureTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try PersistenceController.makeInMemoryContainer()
        DemoData.load(into: context)
    }

    func testMockPricesQuoteKnownItemsInRegionalCurrency() {
        let lines = [
            PlannedGroceryLine(name: "Chicken thighs", quantity: 700, unit: "g", category: "Meat"),
            PlannedGroceryLine(name: "Unicorn dust", quantity: 1, unit: "item", category: "Other")
        ]
        let canada = MockPriceSource().quoteList(for: lines, region: .canada)
        let usa = MockPriceSource().quoteList(for: lines, region: .unitedStates)
        XCTAssertEqual(canada.quotedCount, 1)
        XCTAssertEqual(canada.currency, "CAD")
        XCTAssertEqual(usa.currency, "USD")
        XCTAssertGreaterThan(canada.totalCents, 0)
        XCTAssertNotEqual(canada.totalCents, usa.totalCents, "regions price differently")
    }

    func testAutoPlannerFillsAWeekRespectingDietAndPantry() throws {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let pantry = try context.fetch(FetchDescriptor<Ingredient>())
        let options = AutoPlanner.Options(servingsPerMeal: 2.5, dietTags: ["vegetarian"], pantry: pantry, prices: nil, weeklyBudgetCents: 0)
        let proposals = AutoPlanner().plan(recipes: recipes, options: options)

        XCTAssertFalse(proposals.isEmpty)
        XCTAssertTrue(proposals.allSatisfy { AutoPlanner.fitsDiet($0.recipe, ["vegetarian"]) })
        XCTAssertFalse(proposals.contains { $0.recipe.name.contains("Chicken") || $0.recipe.name.contains("Salmon") })
        XCTAssertTrue(proposals.allSatisfy { $0.servings == 3 })
    }

    func testAutoPlannerHonoursLocksAndExclusions() throws {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let curry = try XCTUnwrap(recipes.first { $0.name == "Chickpea Spinach Curry" })
        var options = AutoPlanner.Options(servingsPerMeal: 2, dietTags: [], pantry: [], prices: nil, weeklyBudgetCents: 0)
        options.locked = [(0, .dinner, curry)]
        options.excludeRecipeNames = ["Veggie Fried Rice"]
        let proposals = AutoPlanner().plan(recipes: recipes, slots: [.init(dayOffset: 0, mealType: .dinner), .init(dayOffset: 1, mealType: .dinner)], options: options)
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals.first?.dayOffset, 1)
        XCTAssertNotEqual(proposals.first?.recipe.name, "Veggie Fried Rice")
        XCTAssertNotEqual(proposals.first?.recipe.name, "Chickpea Spinach Curry")
    }

    func testBudgetModePrefersCheaperMeals() throws {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let lines = recipes.flatMap(\.ingredients).map { PlannedGroceryLine(name: $0.name, quantity: $0.requiredQuantity, unit: $0.unit, category: "") }
        let prices = MockPriceSource().quoteList(for: lines, region: .unitedStates)
        let generous = AutoPlanner().plan(recipes: recipes, slots: [.init(dayOffset: 0, mealType: .dinner)], options: .init(servingsPerMeal: 2, dietTags: [], pantry: [], prices: prices, weeklyBudgetCents: 100_000))
        let tight = AutoPlanner().plan(recipes: recipes, slots: [.init(dayOffset: 0, mealType: .dinner)], options: .init(servingsPerMeal: 2, dietTags: [], pantry: [], prices: prices, weeklyBudgetCents: 500))
        XCTAssertLessThanOrEqual(tight.first?.estimatedCents ?? 0, generous.first?.estimatedCents ?? 0)
    }

    func testSuggestionsSkipSavedRecipesAndFavourPantry() throws {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let pantry = try context.fetch(FetchDescriptor<Ingredient>())
        let suggestions = BuiltInSuggestionSource().rank(savedNames: recipes.map(\.name) + ["Honey Garlic Salmon"], savedTags: recipes.flatMap(\.tagList), pantry: pantry, dietTags: [])
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertFalse(suggestions.contains { $0.name == "Honey Garlic Salmon" })
        XCTAssertTrue(suggestions.first!.reasons.contains { $0.contains("pantry") })

        let vegan = BuiltInSuggestionSource().rank(savedNames: [], savedTags: [], pantry: [], dietTags: ["vegan"])
        XCTAssertFalse(vegan.isEmpty)
        XCTAssertTrue(vegan.allSatisfy { $0.tags.contains("vegan") })
    }

    func testCheckoutProvidersFollowRegion() throws {
        let lines = [PlannedGroceryLine(name: "milk", quantity: 1, unit: "L", category: "Dairy"), PlannedGroceryLine(name: "eggs", quantity: 12, unit: "item", category: "Dairy")]
        let canada = CheckoutProvider.available(in: .canada)
        XCTAssertTrue(canada.contains { $0.key == "pcexpress" })
        XCTAssertFalse(canada.contains { $0.key == "kroger" })
        XCTAssertTrue(CheckoutProvider.available(in: .unitedStates).contains { $0.key == "kroger" })
        let walmart = try XCTUnwrap(canada.first { $0.key == "walmart" }?.url(for: lines, region: .canada))
        XCTAssertEqual(walmart.host(), "www.walmart.ca")
        XCTAssertTrue(walmart.absoluteString.contains("milk"))
    }

    func testSocialCaptionExtraction() {
        let html = """
        <html><head><meta property="og:description" content="Easy 10 minute garlic noodles! 200g noodles, 3 cloves garlic, 2 tbsp soy sauce, 1 tbsp butter. Boil noodles, fry garlic in butter, toss with soy." /></head></html>
        """
        let caption = SocialRecipeImporter.caption(fromHTML: html)
        XCTAssertTrue(caption.hasPrefix("Easy 10 minute garlic noodles"))
        XCTAssertTrue(SocialRecipeImporter.isSocialURL(URL(string: "https://www.tiktok.com/@cook/video/1")!))
        XCTAssertFalse(SocialRecipeImporter.isSocialURL(URL(string: "https://example.com/recipe")!))
    }
}

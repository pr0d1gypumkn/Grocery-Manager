import XCTest
@testable import GroceryManager

final class RecipeImportTests: XCTestCase {
    // MARK: Ingredient lines

    func testParsesFractionsUnitsAndNotes() {
        let line = IngredientLineParser.parse("2 ½ cups all-purpose flour, sifted")
        XCTAssertEqual(line.quantity, 2.5)
        XCTAssertEqual(line.unit, "cup")
        XCTAssertEqual(line.name, "all-purpose flour")
        XCTAssertEqual(line.note, "sifted")
    }

    func testParsesCountWithSizeWord() {
        let line = IngredientLineParser.parse("3 large eggs")
        XCTAssertEqual(line.quantity, 3)
        XCTAssertEqual(line.unit, "item")
        XCTAssertEqual(line.name, "eggs")
        XCTAssertEqual(line.note, "large")
    }

    func testParsesPackageSizes() {
        let line = IngredientLineParser.parse("1 (14 oz) can diced tomatoes")
        XCTAssertEqual(line.quantity, 14)
        XCTAssertEqual(line.unit, "oz")
        XCTAssertEqual(line.name, "diced tomatoes")
        XCTAssertTrue(line.note.contains("14 oz"))
    }

    func testParentheticalsNeverLeakIntoNames() {
        let tortillas = IngredientLineParser.parse("6 (12 inch) flour tortillas")
        XCTAssertEqual(tortillas.quantity, 6)
        XCTAssertEqual(tortillas.unit, "item")
        XCTAssertEqual(tortillas.name, "flour tortillas")
        XCTAssertEqual(tortillas.note, "12 inch")

        let trailing = IngredientLineParser.parse("6 flour tortillas (12 inches)")
        XCTAssertEqual(trailing.name, "flour tortillas")

        let hyphenated = IngredientLineParser.parse("2 (14.5-ounce) cans diced tomatoes")
        XCTAssertEqual(hyphenated.quantity, 29)
        XCTAssertEqual(hyphenated.unit, "oz")
        XCTAssertEqual(hyphenated.name, "diced tomatoes")

        let seasoning = IngredientLineParser.parse("1 (1 ounce) envelope taco seasoning")
        XCTAssertEqual(seasoning.quantity, 1)
        XCTAssertEqual(seasoning.unit, "oz")
        XCTAssertEqual(seasoning.name, "taco seasoning")
    }

    func testCleansModelGeneratedNames() {
        XCTAssertEqual(IngredientLineParser.cleanName("flour tortillas (12 inches").name, "flour tortillas")
        XCTAssertEqual(IngredientLineParser.cleanName("16 ounces) refried beans").name, "refried beans")
        XCTAssertEqual(IngredientLineParser.cleanName("16 ounces) refried beans").note, "16 ounces")
        XCTAssertEqual(IngredientLineParser.cleanName("envelope taco seasoning").name, "taco seasoning")
        XCTAssertEqual(IngredientLineParser.cleanName("Sour cream and salsa").name, "Sour cream and salsa")
    }

    func testParsesRangesContainersAndToTaste() {
        let garlic = IngredientLineParser.parse("2-3 cloves garlic, minced")
        XCTAssertEqual(garlic.quantity, 2)
        XCTAssertEqual(garlic.unit, "item")
        XCTAssertEqual(garlic.name, "garlic")
        XCTAssertTrue(garlic.note.contains("cloves"))

        let salt = IngredientLineParser.parse("Salt to taste")
        XCTAssertEqual(salt.quantity, 1)
        XCTAssertEqual(salt.name, "Salt")
        XCTAssertEqual(salt.note, "to taste")

        let oil = IngredientLineParser.parse("1/4 cup of olive oil")
        XCTAssertEqual(oil.quantity, 0.25)
        XCTAssertEqual(oil.unit, "cup")
        XCTAssertEqual(oil.name, "olive oil")

        let metric = IngredientLineParser.parse("400g chicken thighs")
        XCTAssertEqual(metric.quantity, 400)
        XCTAssertEqual(metric.unit, "g")
        XCTAssertEqual(metric.name, "chicken thighs")
    }

    // MARK: Schema.org

    private let html = """
    <html><head>
    <script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[{"@type":"WebPage","name":"x"},
    {"@type":["Recipe"],"name":"Lemon Chicken","recipeYield":["4","4 servings"],
     "image":{"@type":"ImageObject","url":"https://example.com/chicken.jpg"},
     "prepTime":"PT15M","cookTime":"PT1H","recipeCategory":"Dinner","keywords":"chicken, easy",
     "recipeIngredient":["1 lb chicken breast","2 tbsp olive oil","1 lemon, juiced","Salt &amp; pepper to taste"],
     "recipeInstructions":[{"@type":"HowToSection","name":"Cook","itemListElement":[{"@type":"HowToStep","text":"Season the chicken."},{"@type":"HowToStep","text":"Sear for 6 minutes per side."}]}],
     "nutrition":{"@type":"NutritionInformation","calories":"320 kcal","proteinContent":"35 g","carbohydrateContent":"3 g","fatContent":"18 g"}}]}
    </script></head><body></body></html>
    """

    func testParsesJSONLDRecipeWithGraphAndSections() throws {
        let recipe = try XCTUnwrap(RecipeSchemaParser.parse(html: html, sourceURL: URL(string: "https://example.com/lemon-chicken")))
        XCTAssertEqual(recipe.name, "Lemon Chicken")
        XCTAssertEqual(recipe.servings, 4)
        XCTAssertEqual(recipe.ingredientLines.count, 4)
        XCTAssertEqual(recipe.ingredientLines.last, "Salt & pepper to taste")
        XCTAssertEqual(recipe.instructions, ["Season the chicken.", "Sear for 6 minutes per side."])
        XCTAssertEqual(recipe.imageURL, "https://example.com/chicken.jpg")
        XCTAssertEqual(recipe.prepMinutes, 15)
        XCTAssertEqual(recipe.cookMinutes, 60)
        XCTAssertEqual(recipe.nutritionPerServing?.calories, 320)
        XCTAssertEqual(recipe.nutritionPerServing?.protein, 35)
        XCTAssertEqual(recipe.tags, ["Dinner", "chicken", "easy"])
        XCTAssertEqual(recipe.sourceURL, "https://example.com/lemon-chicken")
    }

    func testDraftFromParsedRecipeHasStructuredIngredients() throws {
        let parsed = try XCTUnwrap(RecipeSchemaParser.parse(html: html))
        let draft = ImportedRecipeDraft(parsed: parsed, method: "schema")
        XCTAssertEqual(draft.ingredients[0].name, "chicken breast")
        XCTAssertEqual(draft.ingredients[0].quantity, 1)
        XCTAssertEqual(draft.ingredients[0].unit, "lb")
        XCTAssertEqual(draft.ingredients[2].name, "lemon")
        XCTAssertEqual(draft.ingredients[2].note, "juiced")
        XCTAssertTrue(draft.instructions.hasPrefix("1. Season"))
    }

    func testPagesWithoutRecipeMarkupReturnNil() {
        XCTAssertNil(RecipeSchemaParser.parse(html: "<html><body><p>Just a blog post</p></body></html>"))
    }

    func testISODurations() {
        XCTAssertEqual(RecipeSchemaParser.minutes(fromISO8601: "PT1H30M"), 90)
        XCTAssertEqual(RecipeSchemaParser.minutes(fromISO8601: "PT45M"), 45)
        XCTAssertEqual(RecipeSchemaParser.minutes(fromISO8601: "P0DT0H20M"), 20)
        XCTAssertEqual(RecipeSchemaParser.minutes(fromISO8601: nil), 0)
    }

    // MARK: Nutrition

    func testNutritionEstimateFromIngredients() {
        let estimate = NutritionEstimator.estimate([
            IngredientRequirement(name: "chicken breast", quantity: 200, unit: "g"),
            IngredientRequirement(name: "olive oil", quantity: 1, unit: "tbsp"),
            IngredientRequirement(name: "eggs", quantity: 2, unit: "item"),
            IngredientRequirement(name: "mystery spice blend", quantity: 1, unit: "tsp")
        ])
        XCTAssertEqual(estimate.matchedCount, 3)
        XCTAssertEqual(estimate.totalCount, 4)
        XCTAssertEqual(estimate.facts.calories, 330 + 884 * 0.135 + 143, accuracy: 3)
        XCTAssertEqual(estimate.facts.protein, 62 + 13, accuracy: 1)
    }
}

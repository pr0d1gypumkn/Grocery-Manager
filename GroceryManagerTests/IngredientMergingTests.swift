import XCTest
@testable import GroceryManager

final class IngredientMergingTests: XCTestCase {
    private let matcher = PantryMatcher()

    func testMergesSameIngredientAcrossUnits() {
        let merged = matcher.merge([
            IngredientRequirement(name: "Onion", quantity: 1, unit: "item"),
            IngredientRequirement(name: "onions", quantity: 2, unit: "item"),
            IngredientRequirement(name: "Flour", quantity: 200, unit: "g"),
            IngredientRequirement(name: "flour", quantity: 0.5, unit: "kg")
        ])

        XCTAssertEqual(merged.count, 2)
        let onion = merged.first { IngredientNameMatcher.matches($0.name, "onion") }
        XCTAssertEqual(onion?.quantity, 3)
        let flour = merged.first { $0.name == "Flour" }
        XCTAssertEqual(flour?.quantity, 700)
        XCTAssertEqual(flour?.unit, "g")
    }

    func testIncompatibleUnitsStaySeparate() {
        let merged = matcher.merge([
            IngredientRequirement(name: "Milk", quantity: 1, unit: "cup"),
            IngredientRequirement(name: "Milk", quantity: 100, unit: "g")
        ])
        XCTAssertEqual(merged.count, 2)
    }

    func testPreparationWordsAndAliasesMatch() {
        XCTAssertTrue(IngredientNameMatcher.matches("diced red onion", "red onions"))
        XCTAssertTrue(IngredientNameMatcher.matches("scallions", "green onion"))
        XCTAssertTrue(IngredientNameMatcher.matches("fresh cilantro, chopped", "Cilantro"))
        XCTAssertFalse(IngredientNameMatcher.matches("green onion", "onion"))
    }

    func testPreparationWordsDroppedWhateverTheLemma() {
        // NLTagger may or may not lemmatise these ("diced" → "dice"); the key must not change.
        XCTAssertEqual(IngredientNameMatcher.key("Diced Carrots"), "carrot")
        XCTAssertEqual(IngredientNameMatcher.key("frozen peas"), "pea")
        XCTAssertEqual(IngredientNameMatcher.key("sliced mushrooms"), "mushroom")
        // A noun that shares a lemma with a preparation verb stays.
        XCTAssertEqual(IngredientNameMatcher.key("pork chops"), "pork chop")
    }

    func testGroceryLinesSkipStockAndSortByAisle() {
        let inventory = [
            Ingredient(name: "Rice", quantity: 1, unit: "kg", category: "Pantry", expiryDate: .distantFuture),
            Ingredient(name: "Chicken breast", quantity: 300, unit: "g", category: "Meat", expiryDate: .distantFuture)
        ]
        let lines = GroceryListBuilder().lines(for: [
            IngredientRequirement(name: "rice", quantity: 300, unit: "g"),
            IngredientRequirement(name: "chicken breast", quantity: 500, unit: "g"),
            IngredientRequirement(name: "broccoli", quantity: 1, unit: "item"),
            IngredientRequirement(name: "eggs", quantity: 2.5, unit: "item")
        ], inventory: inventory)

        XCTAssertEqual(lines.map(\.name), ["broccoli", "chicken breast", "eggs"], "rice is in stock; produce before meat before dairy")
        XCTAssertEqual(lines.first { $0.name == "chicken breast" }?.quantity, 200)
        XCTAssertEqual(lines.first { $0.name == "eggs" }?.quantity, 3, "count units round up to whole items")
        XCTAssertEqual(lines.first { $0.name == "broccoli" }?.category, "Produce")
    }

    func testAisleClassifier() {
        XCTAssertEqual(AisleClassifier.category(for: "Frozen peas"), "Frozen")
        XCTAssertEqual(AisleClassifier.category(for: "Salmon fillets"), "Seafood")
        XCTAssertEqual(AisleClassifier.category(for: "Whole wheat bread"), "Bakery")
        XCTAssertEqual(AisleClassifier.category(for: "Greek yogurt"), "Dairy")
        XCTAssertEqual(AisleClassifier.category(for: "Canned chickpeas"), "Pantry")
        XCTAssertEqual(AisleClassifier.category(for: "Bell pepper"), "Produce")
        XCTAssertEqual(AisleClassifier.category(for: "Paper towels"), "Other")
    }
}

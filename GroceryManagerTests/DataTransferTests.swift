import SwiftData
import XCTest
@testable import GroceryManager

@MainActor
final class DataTransferTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try PersistenceController.makeInMemoryContainer()
    }

    func testJSONExportRoundTrips() throws {
        DemoData.load(into: context)
        let recipesBefore = try context.fetchCount(FetchDescriptor<Recipe>())
        let data = try DataExporter(modelContext: context).json(preferences: nil)

        DemoData.wipe(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 0)

        let summary = try DataImporter(modelContext: context).importFile(data: data, fileName: "mealy-export.json")
        XCTAssertEqual(summary.recipes, recipesBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), recipesBefore)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<Ingredient>()), 10)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<MealPlanEntry>()), 5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StorageLocation>()), 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Household>()).first?.members.count, 3)

        let curry = try XCTUnwrap(try context.fetch(FetchDescriptor<Recipe>()).first { $0.name == "Chickpea Spinach Curry" })
        XCTAssertEqual(curry.ingredients.count, 8)
        XCTAssertEqual(curry.cookMinutes, 25)
        XCTAssertTrue(curry.tagList.contains("vegetarian"))
    }

    func testCSVRoundTripForGroceriesAndPantry() throws {
        let fridge = StorageLocation(name: "Fridge")
        context.insert(fridge)
        context.insert(Ingredient(name: "Milk, whole", quantity: 1, unit: "L", category: "Dairy", location: fridge))
        let grocery = GroceryItem(name: "Bread", quantity: 1, unit: "item", category: "Bakery")
        grocery.note = "sourdough \"the good one\""
        context.insert(grocery)
        try context.save()

        let exporter = DataExporter(modelContext: context)
        let pantryCSV = exporter.pantryCSV()
        let groceriesCSV = exporter.groceriesCSV()
        XCTAssertTrue(pantryCSV.contains("\"Milk, whole\""))

        try context.delete(model: Ingredient.self)
        try context.delete(model: GroceryItem.self)
        let importer = DataImporter(modelContext: context)
        let pantrySummary = try importer.importFile(data: Data(pantryCSV.utf8), fileName: "pantry.csv")
        let grocerySummary = try importer.importFile(data: Data(groceriesCSV.utf8), fileName: "groceries.csv")

        XCTAssertEqual(pantrySummary.pantryItems, 1)
        XCTAssertEqual(grocerySummary.groceries, 1)
        let milk = try XCTUnwrap(try context.fetch(FetchDescriptor<Ingredient>()).first)
        XCTAssertEqual(milk.name, "Milk, whole")
        XCTAssertEqual(milk.location?.name, "Fridge")
        let bread = try XCTUnwrap(try context.fetch(FetchDescriptor<GroceryItem>()).first)
        XCTAssertEqual(bread.note, "sourdough \"the good one\"")
    }

    func testImportsSchemaOrgRecipeJSONAndPaprikaObjects() throws {
        let schema = """
        [{"@type":"Recipe","name":"Toast","recipeIngredient":["2 slices bread","1 tbsp butter"],"recipeInstructions":"Toast the bread. Spread butter.","recipeYield":"1"}]
        """
        var summary = try DataImporter(modelContext: context).importFile(data: Data(schema.utf8), fileName: "recipes.json")
        XCTAssertEqual(summary.recipes, 1)

        let paprika = """
        {"name":"Pancakes","ingredients":"1 cup flour\\n1 egg\\n1 cup milk","directions":"Mix.\\nFry.","servings":"4","prep_time":"10 min","cook_time":"15 min","categories":["Breakfast"],"nutritional_info":"Calories: 210, Protein: 6g"}
        """
        summary = try DataImporter(modelContext: context).importFile(data: Data(paprika.utf8), fileName: "pancakes.json")
        XCTAssertEqual(summary.recipes, 1)
        let pancakes = try XCTUnwrap(try context.fetch(FetchDescriptor<Recipe>()).first { $0.name == "Pancakes" })
        XCTAssertEqual(pancakes.servings, 4)
        XCTAssertEqual(pancakes.ingredients.count, 3)
        XCTAssertEqual(pancakes.prepMinutes, 10)
        XCTAssertEqual(pancakes.caloriesPerServing, 210)
        XCTAssertEqual(pancakes.tagList, ["Breakfast"])
    }

    func testGzipAndZipReaders() throws {
        // "hello" gzip-compressed (python: gzip.compress(b"hello"))
        let gzipped = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00, 0x86, 0xa6, 0x10, 0x36, 0x05, 0x00, 0x00, 0x00])
        XCTAssertEqual(Gzip.decompress(gzipped).map { String(decoding: $0, as: UTF8.self) }, "hello")

        // A stored (uncompressed) zip with one entry "a.txt" containing "hi"
        var zip = Data()
        let name = Array("a.txt".utf8), body = Array("hi".utf8)
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)] }
        let local: [UInt8] = [0x50, 0x4b, 0x03, 0x04] + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(body.count) + le32(body.count) + le16(name.count) + le16(0) + name + body
        let centralOffset = local.count
        let central: [UInt8] = [0x50, 0x4b, 0x01, 0x02] + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(body.count) + le32(body.count) + le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(0) + name
        let eocd: [UInt8] = [0x50, 0x4b, 0x05, 0x06] + le16(0) + le16(0) + le16(1) + le16(1) + le32(central.count) + le32(centralOffset) + le16(0)
        zip.append(contentsOf: local + central + eocd)

        let entries = try ZipArchive.entries(in: zip)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "a.txt")
        XCTAssertEqual(entries.first.map { String(decoding: $0.data, as: UTF8.self) }, "hi")
    }

    func testUseItUpSuggestsRecipesForExpiringStock() throws {
        DemoData.load(into: context)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let inventory = try context.fetch(FetchDescriptor<Ingredient>())
        let suggestions = UseItUpSuggester.suggestions(recipes: recipes, inventory: inventory)
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.allSatisfy { !$0.expiringIngredients.isEmpty })
        XCTAssertTrue(suggestions.contains { $0.expiringIngredients.contains("Chicken thighs") || $0.expiringIngredients.contains("Spinach") })
    }
}

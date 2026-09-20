import XCTest
@testable import GroceryManager

final class ExpiryNotificationPlannerTests: XCTestCase {
    func testPlansIncludeItemsExpiringWithinThreeDays() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let planner = ExpiryNotificationPlanner(calendar: Calendar(identifier: .gregorian))
        let ingredient = Ingredient(name: "Milk", expiryDate: now.addingTimeInterval(3 * 24 * 60 * 60))

        let plans = planner.plans(for: [ingredient], now: now)

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.title, "Ingredient expiring soon")
        XCTAssertTrue(plans.first?.body.contains("Milk") == true)
    }

    func testPlansExcludeExpiredAndLaterItems() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let planner = ExpiryNotificationPlanner(calendar: Calendar(identifier: .gregorian))
        let expired = Ingredient(name: "Yogurt", expiryDate: now.addingTimeInterval(-60))
        let later = Ingredient(name: "Rice", expiryDate: now.addingTimeInterval(4 * 24 * 60 * 60))

        let plans = planner.plans(for: [expired, later], now: now)

        XCTAssertTrue(plans.isEmpty)
    }

    func testPlansAreSortedByExpiryDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let planner = ExpiryNotificationPlanner(calendar: Calendar(identifier: .gregorian))
        let later = Ingredient(name: "Bread", expiryDate: now.addingTimeInterval(2 * 24 * 60 * 60))
        let sooner = Ingredient(name: "Eggs", expiryDate: now.addingTimeInterval(24 * 60 * 60))

        let plans = planner.plans(for: [later, sooner], now: now)

        XCTAssertEqual(plans.count, 2)
        XCTAssertTrue(plans[0].body.contains("Eggs"))
        XCTAssertTrue(plans[1].body.contains("Bread"))
        XCTAssertLessThan(plans[0].date, plans[1].date)
    }

    func testStorageLocationShelfRowsFillTwoItemsPerShelf() {
        let ingredients = [
            Ingredient(name: "Milk", category: "Dairy"),
            Ingredient(name: "Eggs", category: "Dairy"),
            Ingredient(name: "Tomatoes", category: "Produce"),
            Ingredient(name: "Cereal", category: "Pantry"),
            Ingredient(name: "Yogurt", category: "Dairy"),
            Ingredient(name: "Spinach", category: "Produce")
        ]

        let rows = LocationShelfLayout.rows(for: ingredients)

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].count, 2)
        XCTAssertEqual(rows[0][0]?.name, "Milk")
        XCTAssertEqual(rows[0][1]?.name, "Eggs")
        XCTAssertEqual(rows[1][0]?.name, "Tomatoes")
        XCTAssertEqual(rows[1][1]?.name, "Cereal")
        XCTAssertEqual(rows[2][0]?.name, "Yogurt")
        XCTAssertEqual(rows[2][1]?.name, "Spinach")
    }

    func testStorageLocationShelfRowsPadShortRowsToTwoSlots() {
        let ingredients = [Ingredient(name: "Milk", category: "Dairy")]

        let rows = LocationShelfLayout.rows(for: ingredients)

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].count, 2)
        XCTAssertEqual(rows[0][0]?.name, "Milk")
        XCTAssertNil(rows[0][1])
        XCTAssertNil(rows[1][0])
        XCTAssertNil(rows[2][1])
    }

    func testPersistenceUsesCloudKitSyncConfiguration() {
        let configuration = PersistenceController.makeConfiguration()

        XCTAssertEqual(configuration.cloudKitDatabase, .automatic)
    }
}

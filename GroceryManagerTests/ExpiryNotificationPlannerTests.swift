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
}

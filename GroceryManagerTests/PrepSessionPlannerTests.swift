import XCTest
@testable import GroceryManager

final class PrepSessionPlannerTests: XCTestCase {
    private let recipes = [
        PrepRecipeInput(name: "Chicken bowls", instructions: "Preheat the oven to 425°F.\nDice the onion.\nRoast the chicken for 25 minutes.\nServe over rice.", ingredientNames: ["chicken thighs", "onion", "rice"], servings: 4),
        PrepRecipeInput(name: "Curry", instructions: "Dice the onion and mince the garlic.\nSimmer the chickpeas with tomatoes for 15 minutes.\nStir in spinach.", ingredientNames: ["chickpeas", "onion", "garlic", "spinach", "rice"], servings: 4)
    ]

    func testSharedPrepComesFirstAndCoversPerRecipeKnifeWork() {
        let plan = PrepSessionPlanner().plan(recipes)
        let titles = plan.steps.map(\.title)

        XCTAssertEqual(plan.recipes.map(\.name), ["Chicken bowls", "Curry"])
        XCTAssertTrue(titles.contains("Preheat the oven to 425°F"), "\(titles)")
        XCTAssertTrue(titles.contains { $0.hasPrefix("Dice onion") }, "\(titles)")
        XCTAssertTrue(titles.contains { $0.contains("rice in one batch") }, "\(titles)")
        XCTAssertFalse(titles.contains("Dice the onion."), "the per-recipe step is covered by shared knife work")
        XCTAssertEqual(titles.filter { $0.lowercased().contains("preheat") }.count, 1)

        let firstRecipeStep = try! XCTUnwrap(plan.steps.first { !$0.id.hasPrefix("shared-") })
        let lastSharedStep = try! XCTUnwrap(plan.steps.last { $0.id.hasPrefix("shared-") })
        XCTAssertGreaterThan(firstRecipeStep.group, lastSharedStep.group)
    }

    func testStepsRunInParallelOnDifferentStations() {
        let plan = PrepSessionPlanner().plan(recipes)
        let roast = try! XCTUnwrap(plan.steps.first { $0.title.hasPrefix("Roast") })
        let simmer = try! XCTUnwrap(plan.steps.first { $0.title.hasPrefix("Simmer") })
        XCTAssertEqual(roast.lane, .oven)
        XCTAssertEqual(simmer.lane, .stove)
        XCTAssertEqual(roast.timerMinutes, 25)
        XCTAssertEqual(simmer.timerMinutes, 15)
        XCTAssertEqual(roast.group, simmer.group, "oven and stove steps share a group")
        XCTAssertGreaterThan(plan.estimatedMinutes, 0)
        XCTAssertLessThan(plan.estimatedMinutes, plan.steps.reduce(0) { $0 + $1.minutes }, "parallel steps overlap")
    }

    func testSameLaneStepsNeverShareAGroup() {
        let plan = PrepSessionPlanner().plan([
            PrepRecipeInput(name: "A", instructions: "Simmer for 10 minutes.", ingredientNames: ["a"], servings: 1),
            PrepRecipeInput(name: "B", instructions: "Boil for 12 minutes.", ingredientNames: ["b"], servings: 1)
        ])
        for group in plan.groups {
            let stove = group.filter { $0.lane == .stove }
            XCTAssertLessThanOrEqual(stove.count, 1, "\(group.map(\.title))")
        }
    }

    func testLaneDetectionAndDurations() {
        XCTAssertEqual(PrepSessionPlanner.lane(for: "Bake for 20 minutes."), .oven)
        XCTAssertEqual(PrepSessionPlanner.lane(for: "Marinate the chicken for 30 minutes."), .passive)
        XCTAssertEqual(PrepSessionPlanner.lane(for: "Slice the peppers."), .prep)
        XCTAssertEqual(PrepSessionPlanner.lane(for: "Toss everything together and serve."), .assemble)
        XCTAssertEqual(PrepSessionPlanner.lane(for: "Simmer in a Dutch oven for 1 hour."), .stove)
        XCTAssertEqual(PrepSessionPlanner.minutes(in: "Roast for 10-12 minutes"), 12)
        XCTAssertEqual(PrepSessionPlanner.minutes(in: "Simmer for 1 hour"), 60)
        XCTAssertNil(PrepSessionPlanner.minutes(in: "Stir well"))
    }

    func testPlanRoundTripsThroughJSON() throws {
        let plan = PrepSessionPlanner().plan(recipes)
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(PrepPlan.self, from: data)
        XCTAssertEqual(decoded, plan)
    }
}

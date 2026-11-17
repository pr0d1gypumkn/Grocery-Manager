import XCTest
@testable import GroceryManager

final class UnitConversionTests: XCTestCase {
    func testMassConversions() {
        XCTAssertEqual(UnitConverter.convert(1, from: "kg", to: "g"), 1000)
        XCTAssertEqual(UnitConverter.convert(1, from: "lb", to: "oz")!, 16, accuracy: 0.0001)
        XCTAssertEqual(UnitConverter.convert(453.59237, from: "g", to: "lb")!, 1, accuracy: 0.0001)
    }

    func testVolumeConversions() {
        XCTAssertEqual(UnitConverter.convert(1, from: "cup", to: "tbsp")!, 16, accuracy: 0.0001)
        XCTAssertEqual(UnitConverter.convert(3, from: "tsp", to: "tbsp")!, 1, accuracy: 0.0001)
        XCTAssertEqual(UnitConverter.convert(1, from: "L", to: "ml"), 1000)
        XCTAssertEqual(UnitConverter.convert(1, from: "gal", to: "qt")!, 4, accuracy: 0.0001)
    }

    func testCountConversions() {
        XCTAssertEqual(UnitConverter.convert(2, from: "dozen", to: "item"), 24)
        XCTAssertEqual(UnitConverter.convert(3, from: "serving", to: "item"), 3)
    }

    func testIncompatibleDimensionsReturnNil() {
        XCTAssertNil(UnitConverter.convert(1, from: "g", to: "ml"))
        XCTAssertNil(UnitConverter.convert(1, from: "item", to: "g"))
        XCTAssertNil(UnitConverter.convert(1, from: "banana", to: "g"))
    }

    func testRoundTripIsStable() {
        let grams = UnitConverter.convert(2.5, from: "lb", to: "g")!
        XCTAssertEqual(UnitConverter.convert(grams, from: "g", to: "lb")!, 2.5, accuracy: 0.000001)
    }

    func testDisplayConversionFollowsUnitSystem() {
        let imperial = UnitConverter.display(500, unit: "g", system: .imperial)
        XCTAssertEqual(imperial.unit, "lb")
        XCTAssertEqual(imperial.quantity, 1.1, accuracy: 0.01)

        let metric = UnitConverter.display(2, unit: "cup", system: .metric)
        XCTAssertEqual(metric.unit, "ml")
        XCTAssertEqual(metric.quantity, 473.18, accuracy: 0.01)

        let large = UnitConverter.display(1500, unit: "g", system: .metric)
        XCTAssertEqual(large.unit, "g", "already metric: left alone")

        let spoons = UnitConverter.display(2, unit: "tbsp", system: .metric)
        XCTAssertEqual(spoons.unit, "tbsp", "spoon measures are universal")
    }
}

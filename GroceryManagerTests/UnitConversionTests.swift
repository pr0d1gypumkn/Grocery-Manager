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

    // MARK: Quantity steps

    func testStepSnapsToTidyMultiples() {
        XCTAssertEqual(QuantityStep.stepped(237, unit: "g", up: true), 250)
        XCTAssertEqual(QuantityStep.stepped(237, unit: "g", up: false), 200)
        XCTAssertEqual(QuantityStep.stepped(90, unit: "g", up: true), 100)
        XCTAssertEqual(QuantityStep.stepped(100, unit: "g", up: false), 90)
        XCTAssertEqual(QuantityStep.stepped(1000, unit: "ml", up: true), 1100)
    }

    func testStepSizeFollowsTheUnit() {
        XCTAssertEqual(QuantityStep.stepped(1, unit: "item", up: true), 2)
        XCTAssertEqual(QuantityStep.stepped(1.5, unit: "item", up: true), 2)
        XCTAssertEqual(QuantityStep.stepped(0.5, unit: "cup", up: true), 0.75)
        XCTAssertEqual(QuantityStep.stepped(1, unit: "kg", up: false), 0.75)
        XCTAssertEqual(QuantityStep.stepped(2, unit: "tbsp", up: true), 2.5)
    }

    func testStepNeverGoesNegative() {
        XCTAssertEqual(QuantityStep.stepped(0, unit: "item", up: false), 0)
        XCTAssertEqual(QuantityStep.stepped(5, unit: "g", up: false), 0)
    }

    func testUnitMenuPutsTheUserSystemFirst() {
        XCTAssertEqual(QuantityUnit.menuLayout(for: .metric).sections[1].units.first, .grams)
        XCTAssertEqual(QuantityUnit.menuLayout(for: .imperial).sections[1].units.first, .ounces)
    }

    func testUnitMenuOffersEveryUnitExactlyOnce() {
        for system in UnitSystem.allCases {
            let layout = QuantityUnit.menuLayout(for: system)
            let units = (layout.sections + layout.submenus).flatMap(\.units)
            XCTAssertEqual(Set(units), Set(QuantityUnit.allCases), "\(system)")
            XCTAssertEqual(units.count, QuantityUnit.allCases.count, "\(system)")
        }
    }

    func testUnitLabelsPluralize() {
        XCTAssertEqual(QuantityUnit.label("item", quantity: 1), "item")
        XCTAssertEqual(QuantityUnit.label("item", quantity: 3), "items")
        XCTAssertEqual(QuantityUnit.label("cup", quantity: 0.5), "cups")
        XCTAssertEqual(QuantityUnit.label("g", quantity: 250), "g")
    }
}

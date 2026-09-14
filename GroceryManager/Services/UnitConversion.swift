import Foundation

enum UnitConverter {
    private enum Dimension {
        case count
        case mass
        case volume
    }

    static func convert(_ quantity: Double, from source: String, to target: String) -> Double? {
        guard let sourceUnit = QuantityUnit(rawValue: source),
              let targetUnit = QuantityUnit(rawValue: target),
              let sourceBase = toBase(quantity, unit: sourceUnit),
              let targetBase = toBase(1, unit: targetUnit),
              dimension(for: sourceUnit) == dimension(for: targetUnit) else {
            return nil
        }

        return sourceBase / targetBase
    }

    private static func toBase(_ quantity: Double, unit: QuantityUnit) -> Double? {
        switch unit {
        case .item:
            return quantity
        case .dozen:
            return quantity * 12
        case .grams:
            return quantity
        case .kilograms:
            return quantity * 1_000
        case .ounces:
            return quantity * 28.349523125
        case .pounds:
            return quantity * 453.59237
        case .milliliters:
            return quantity
        case .liters:
            return quantity * 1_000
        case .fluidOunces:
            return quantity * 29.5735295625
        case .teaspoons:
            return quantity * 4.92892159375
        case .tablespoons:
            return quantity * 14.78676478125
        case .cups:
            return quantity * 236.5882365
        case .pints:
            return quantity * 473.176473
        case .quarts:
            return quantity * 946.352946
        case .gallons:
            return quantity * 3785.411784
        case .pinches:
            return quantity * 0.3080575996
        case .dashes:
            return quantity * 0.6161151992
        case .smidgens:
            return quantity * 0.1540287998
        }
    }

    private static func dimension(for unit: QuantityUnit) -> Dimension {
        switch unit {
        case .item, .dozen: .count
        case .grams, .kilograms, .ounces, .pounds: .mass
        case .milliliters, .liters, .fluidOunces, .teaspoons, .tablespoons, .cups, .pints, .quarts, .gallons, .pinches, .dashes, .smidgens: .volume
        }
    }
}

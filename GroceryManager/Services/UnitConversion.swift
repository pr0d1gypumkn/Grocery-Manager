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
        case .grams:
            return quantity
        case .kilograms:
            return quantity * 1_000
        case .ounces:
            return quantity * 28.349523125
        case .milliliters:
            return quantity
        case .liters:
            return quantity * 1_000
        }
    }

    private static func dimension(for unit: QuantityUnit) -> Dimension {
        switch unit {
        case .item: .count
        case .grams, .kilograms, .ounces: .mass
        case .milliliters, .liters: .volume
        }
    }
}

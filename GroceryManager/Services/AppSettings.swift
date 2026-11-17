import Foundation
import Observation
import SwiftUI

enum Region: String, CaseIterable, Identifiable, Codable {
    case unitedStates = "US"
    case canada = "CA"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unitedStates: "United States"
        case .canada: "Canada"
        }
    }

    var currencyCode: String {
        switch self {
        case .unitedStates: "USD"
        case .canada: "CAD"
        }
    }

    var defaultUnitSystem: UnitSystem {
        switch self {
        case .unitedStates: .imperial
        case .canada: .metric
        }
    }

    /// Best guess from the device locale; the user can change it in Settings.
    static var detected: Region {
        Locale.current.region?.identifier == "CA" ? .canada : .unitedStates
    }
}

enum UnitSystem: String, CaseIterable, Identifiable, Codable {
    case metric
    case imperial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metric: "Metric (g, ml)"
        case .imperial: "Imperial (oz, cups)"
        }
    }
}

/// User preferences that are not part of the synced data model. Backed by UserDefaults so
/// they are available before any store loads and can be read from intents.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedRegion = defaults.string(forKey: Keys.region) ?? Region.detected.rawValue
        regionRaw = storedRegion
        unitSystemRaw = defaults.string(forKey: Keys.unitSystem) ?? (Region(rawValue: storedRegion) ?? .detected).defaultUnitSystem.rawValue
        weeklyBudgetCents = defaults.integer(forKey: Keys.weeklyBudget)
        dietTagsRaw = defaults.string(forKey: Keys.dietTags) ?? ""
        didSeedDemoData = defaults.bool(forKey: Keys.didSeedDemo)
        autoBuildGroceryList = defaults.object(forKey: Keys.autoBuild) as? Bool ?? true
        autoStockOnCheck = defaults.object(forKey: Keys.autoStock) as? Bool ?? true
    }

    private enum Keys {
        static let region = "settings.region"
        static let unitSystem = "settings.unitSystem"
        static let weeklyBudget = "settings.weeklyBudgetCents"
        static let dietTags = "settings.dietTags"
        static let didSeedDemo = "settings.didSeedDemoData"
        static let autoBuild = "settings.autoBuildGroceryList"
        static let autoStock = "settings.autoStockOnCheck"
    }

    private var regionRaw: String { didSet { defaults.set(regionRaw, forKey: Keys.region) } }
    private var unitSystemRaw: String { didSet { defaults.set(unitSystemRaw, forKey: Keys.unitSystem) } }
    private var dietTagsRaw: String { didSet { defaults.set(dietTagsRaw, forKey: Keys.dietTags) } }

    var region: Region {
        get { Region(rawValue: regionRaw) ?? .detected }
        set { regionRaw = newValue.rawValue }
    }

    var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
        set { unitSystemRaw = newValue.rawValue }
    }

    var currencyCode: String { region.currencyCode }

    /// Weekly grocery budget in cents; 0 means budget mode is off.
    var weeklyBudgetCents: Int { didSet { defaults.set(weeklyBudgetCents, forKey: Keys.weeklyBudget) } }

    var dietTags: [String] {
        get { dietTagsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        set { dietTagsRaw = newValue.joined(separator: ", ") }
    }

    var didSeedDemoData: Bool { didSet { defaults.set(didSeedDemoData, forKey: Keys.didSeedDemo) } }

    /// Rebuild the grocery list whenever the week's plan or stock changes.
    var autoBuildGroceryList: Bool { didSet { defaults.set(autoBuildGroceryList, forKey: Keys.autoBuild) } }

    /// Checking off a grocery item puts it straight into stock.
    var autoStockOnCheck: Bool { didSet { defaults.set(autoStockOnCheck, forKey: Keys.autoStock) } }

    func formatPrice(cents: Int, currency: String? = nil) -> String {
        let value = Decimal(cents) / 100
        return value.formatted(.currency(code: currency ?? currencyCode).precision(.fractionLength(2)))
    }
}

// MARK: - Display conversion

extension UnitConverter {
    /// Converts a stored quantity into the unit the user prefers to read, e.g. 453 g → 1 lb
    /// for imperial users. Count units and spoon measures are left alone.
    static func display(_ quantity: Double, unit: String, system: UnitSystem) -> (quantity: Double, unit: String) {
        guard let source = QuantityUnit(rawValue: unit) else { return (quantity, unit) }
        let target: QuantityUnit
        switch (system, source) {
        case (.metric, .ounces), (.metric, .pounds):
            let grams = convert(quantity, from: unit, to: QuantityUnit.grams.rawValue) ?? quantity
            target = grams >= 1000 ? .kilograms : .grams
        case (.metric, .fluidOunces), (.metric, .cups), (.metric, .pints), (.metric, .quarts), (.metric, .gallons):
            let ml = convert(quantity, from: unit, to: QuantityUnit.milliliters.rawValue) ?? quantity
            target = ml >= 1000 ? .liters : .milliliters
        case (.imperial, .grams), (.imperial, .kilograms):
            let grams = convert(quantity, from: unit, to: QuantityUnit.grams.rawValue) ?? quantity
            target = grams >= 453.59237 ? .pounds : .ounces
        case (.imperial, .milliliters), (.imperial, .liters):
            let ml = convert(quantity, from: unit, to: QuantityUnit.milliliters.rawValue) ?? quantity
            target = ml >= 946 ? .quarts : (ml >= 59 ? .cups : .fluidOunces)
        default:
            return (quantity, unit)
        }
        guard let converted = convert(quantity, from: unit, to: target.rawValue) else { return (quantity, unit) }
        return ((converted * 100).rounded() / 100, target.rawValue)
    }

    static func displayText(_ quantity: Double, unit: String, system: UnitSystem) -> String {
        let shown = display(quantity, unit: unit, system: system)
        return "\(shown.quantity.quantityText) \(shown.unit)"
    }
}

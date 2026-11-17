import Foundation
import SwiftData

/// Where batch-cooked food is kept, which decides its default shelf life.
enum BatchStorage: String, CaseIterable, Identifiable, Codable {
    case fridge = "Fridge"
    case freezer = "Freezer"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .fridge: "refrigerator.fill"
        case .freezer: "snowflake"
        }
    }

    /// How long a cooked portion keeps, in days.
    var shelfLifeDays: Int {
        switch self {
        case .fridge: 4
        case .freezer: 90
        }
    }
}

/// One batch-cooking session built from a week's plan. The step list is stored as JSON so
/// the generated plan survives recipe edits, and so it syncs as a single blob.
@Model
final class PrepSession {
    var date: Date = Date.now
    var weekStart: Date = Date.now
    var title: String = ""
    var planJSON: Data = Data()
    var completedStepIDs: [String] = []
    var isCompleted: Bool = false
    var estimatedMinutes: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \PrepBatch.session)
    var storedBatches: [PrepBatch]? = []

    var batches: [PrepBatch] {
        get { storedBatches ?? [] }
        set { storedBatches = newValue }
    }

    init(date: Date = .now, weekStart: Date, title: String, plan: PrepPlan) {
        self.date = date
        self.weekStart = Calendar.current.startOfDay(for: weekStart)
        self.title = title
        self.planJSON = (try? JSONEncoder().encode(plan)) ?? Data()
        self.estimatedMinutes = plan.estimatedMinutes
    }

    var plan: PrepPlan? {
        try? JSONDecoder().decode(PrepPlan.self, from: planJSON)
    }
}

/// Portions of one recipe cooked in a prep session, tracked as stock until eaten.
@Model
final class PrepBatch {
    var name: String = ""
    var portions: Int = 0
    var portionsLeft: Int = 0
    var container: String = ""
    var storageRaw: String = BatchStorage.fridge.rawValue
    var madeOn: Date = Date.now
    var expiryDate: Date = Date.now

    var recipe: Recipe?
    var session: PrepSession?
    /// The inventory row that shows these portions in the pantry/fridge/freezer.
    var stockItem: Ingredient?

    @Relationship(deleteRule: .nullify, inverse: \MealPlanEntry.batch)
    var storedMeals: [MealPlanEntry]? = []

    var meals: [MealPlanEntry] {
        get { storedMeals ?? [] }
        set { storedMeals = newValue }
    }

    var storage: BatchStorage {
        get { BatchStorage(rawValue: storageRaw) ?? .fridge }
        set { storageRaw = newValue.rawValue }
    }

    init(name: String, portions: Int, container: String, storage: BatchStorage, madeOn: Date = .now, recipe: Recipe? = nil) {
        self.name = name
        self.portions = portions
        self.portionsLeft = portions
        self.container = container
        self.storageRaw = storage.rawValue
        self.madeOn = madeOn
        self.expiryDate = Calendar.current.date(byAdding: .day, value: storage.shelfLifeDays, to: madeOn) ?? madeOn
        self.recipe = recipe
    }
}

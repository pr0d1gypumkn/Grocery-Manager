import Foundation
import OSLog
import SwiftData

enum PersistenceController {
    /// Must match the iCloud container in GroceryManager.entitlements
    /// (Signing & Capabilities ▸ iCloud ▸ Containers).
    static let cloudKitContainerID = "iCloud.work.pumpkinpatch.mealy"

    static let schema = Schema([
        StorageLocation.self,
        Ingredient.self,
        Recipe.self,
        RecipeIngredient.self,
        GroceryItem.self,
        MealPlanEntry.self,
        PrepSession.self,
        PrepBatch.self,
        Household.self,
        HouseholdMember.self
    ])

    private static let logger = Logger(subsystem: "work.pumpkinpatch.mealy", category: "Persistence")

    /// Data syncs through the user's private CloudKit database. SwiftData mirrors
    /// changes in the background and merges remote changes into `mainContext`,
    /// so `@Query` views update by themselves when another device edits something.
    static func makeConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
    }

    /// An isolated in-memory container for previews and tests.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: schema, configurations: [makeConfiguration()])
        } catch {
            // Most likely a missing/mismatched iCloud entitlement. Keep the app usable
            // with the same on-disk store, just without sync, instead of crashing.
            logger.error("CloudKit-backed store failed to load, falling back to local-only: \(error)")
            do {
                let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
                return try ModelContainer(for: schema, configurations: [local])
            } catch {
                // Last resort: an in-memory store so the app opens instead of crashing.
                logger.fault("Local store failed to load, using in-memory store: \(error)")
                return try! makeInMemoryContainer()
            }
        }
    }()
}

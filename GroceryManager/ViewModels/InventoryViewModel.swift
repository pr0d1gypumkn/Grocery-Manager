import Foundation
import SwiftData

@MainActor
final class InventoryViewModel: ObservableObject {
    enum ExpiryState {
        case fresh
        case soon
        case expired

        var label: String {
            switch self {
            case .fresh: "Fresh"
            case .soon: "Expiring soon"
            case .expired: "Expired"
            }
        }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveLocation(existing location: StorageLocation?, name: String, icon: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let location {
            location.name = trimmedName
            location.icon = icon
        } else {
            modelContext.insert(StorageLocation(name: trimmedName, icon: icon))
        }
        saveChanges()
    }

    func saveIngredient(
        existing ingredient: Ingredient?,
        name: String,
        quantity: Double,
        unit: String,
        initialQuantity: Double,
        reorderThreshold: Double,
        category: String,
        expiryDate: Date,
        location: StorageLocation?
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let ingredient {
            ingredient.name = trimmedName
            ingredient.quantity = max(quantity, 0)
            ingredient.unit = unit
            ingredient.initialQuantity = max(initialQuantity, ingredient.quantity)
            ingredient.reorderThreshold = max(reorderThreshold, 0)
            ingredient.category = category
            ingredient.expiryDate = expiryDate
            ingredient.location = location
        } else {
            modelContext.insert(Ingredient(
                name: trimmedName,
                quantity: max(quantity, 0),
                unit: unit,
                initialQuantity: max(initialQuantity, quantity),
                reorderThreshold: max(reorderThreshold, 0),
                category: category,
                expiryDate: expiryDate,
                location: location
            ))
        }
        saveChanges()
    }

    func delete<T: PersistentModel>(_ model: T) {
        modelContext.delete(model)
        saveChanges()
    }

    func expiryState(for date: Date, now: Date = .now) -> ExpiryState {
        if date < now { return .expired }
        if date <= Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now {
            return .soon
        }
        return .fresh
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Could not save grocery data: \(error)")
        }
    }
}

import Foundation
import SwiftData

@MainActor
final class GroceryViewModel: ObservableObject {
    

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }


    func saveGrocery(
        existing grocery: GroceryItem?,
        name: String,
        quantity: Double,
        unit: String,
        category: String?
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let grocery {
            grocery.name = trimmedName
            grocery.quantity = max(quantity, 0)
            grocery.unit = unit
            grocery.category = category ?? "Other"
        } else {
            modelContext.insert(GroceryItem(
                name: trimmedName,
                quantity: max(quantity, 0),
                unit: unit,
                category: category
            ))
        }
        saveChanges()
    }

    func delete<T: PersistentModel>(_ model: T) {
        modelContext.delete(model)
        saveChanges()
    }


    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Could not save grocery data: \(error)")
        }
    }
}

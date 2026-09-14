import SwiftData
import SwiftUI

struct LocationFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let location: StorageLocation?
    @State private var name: String
    @State private var icon: String

    private let icons = ["refrigerator", "archivebox", "shippingbox", "cabinet", "fork.knife"]

    init(location: StorageLocation? = nil) {
        self.location = location
        _name = State(initialValue: location?.name ?? "")
        _icon = State(initialValue: location?.icon ?? "shippingbox")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Icon", selection: $icon) {
                    ForEach(icons, id: \.self) { icon in
                        Label(icon.capitalized, systemImage: icon).tag(icon)
                    }
                }
            }
            .navigationTitle(location == nil ? "New Storage" : "Edit Storage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        InventoryViewModel(modelContext: modelContext).saveLocation(existing: location, name: name, icon: icon)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct IngredientFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]

    let ingredient: Ingredient?
    let defaultLocation: StorageLocation?
    @State private var name: String
    @State private var quantity: Double
    @State private var unit: String
    @State private var initialQuantity: Double
    @State private var reorderThreshold: Double
    @State private var category: String
    @State private var expiryDate: Date
    @State private var selectedLocation: StorageLocation?

    private let categories = ["Produce", "Dairy", "Meat", "Pantry", "Frozen", "Beverages", "Other"]

    init(ingredient: Ingredient? = nil, defaultLocation: StorageLocation? = nil) {
        self.ingredient = ingredient
        self.defaultLocation = defaultLocation
        _name = State(initialValue: ingredient?.name ?? "")
        _quantity = State(initialValue: ingredient?.quantity ?? 1)
        _unit = State(initialValue: ingredient?.unit ?? "item")
        _initialQuantity = State(initialValue: max(ingredient?.initialQuantity ?? 1, ingredient?.quantity ?? 1))
        _reorderThreshold = State(initialValue: ingredient?.reorderThreshold ?? 0)
        _category = State(initialValue: ingredient?.category ?? "Other")
        _expiryDate = State(initialValue: ingredient?.expiryDate ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
        _selectedLocation = State(initialValue: ingredient?.location ?? defaultLocation)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Quantity", value: $quantity, format: .number)
                    .keyboardType(.decimalPad)
                Stepper(value: $quantity, in: 0...999, step: 0.5) {
                    LabeledContent("Quantity", value: quantity.formatted(.number.precision(.fractionLength(0...2))))
                }
                TextField("Starting quantity", value: $initialQuantity, format: .number)
                    .keyboardType(.decimalPad)
                Stepper(value: $initialQuantity, in: max(quantity, 0)...999, step: 0.5) {
                    LabeledContent("Starting quantity", value: initialQuantity.formatted(.number.precision(.fractionLength(0...2))))
                }
                TextField("Replenish below", value: $reorderThreshold, format: .number)
                    .keyboardType(.decimalPad)
                Stepper(value: $reorderThreshold, in: 0...999, step: 0.5) {
                    LabeledContent("Replenish below", value: reorderThreshold.formatted(.number.precision(.fractionLength(0...2))))
                }
                Picker("Unit", selection: $unit) {
                    ForEach(QuantityUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self, content: Text.init)
                }
                DatePicker("Expiration date", selection: $expiryDate, displayedComponents: .date)
                Picker("Storage location", selection: $selectedLocation) {
                    Text("Unassigned").tag(nil as StorageLocation?)
                    ForEach(locations) { location in
                        Text(location.name).tag(location as StorageLocation?)
                    }
                }
            }
            .navigationTitle(ingredient == nil ? "New Ingredient" : "Edit Ingredient")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        InventoryViewModel(modelContext: modelContext).saveIngredient(existing: ingredient, name: name, quantity: quantity, unit: unit, initialQuantity: initialQuantity, reorderThreshold: reorderThreshold, category: category, expiryDate: expiryDate, location: selectedLocation)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

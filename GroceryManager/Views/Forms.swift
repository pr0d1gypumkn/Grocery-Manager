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

    // New items get smart defaults from the name until the user sets a field themselves.
    @State private var didSetCategory: Bool
    @State private var didSetExpiry: Bool
    @State private var didSetLocation: Bool
    @State private var didSetFullAmount: Bool

    private let categories = CategoryStyle.all

    init(ingredient: Ingredient? = nil, defaultLocation: StorageLocation? = nil) {
        self.ingredient = ingredient
        self.defaultLocation = defaultLocation
        let isNew = ingredient == nil
        _name = State(initialValue: ingredient?.name ?? "")
        _quantity = State(initialValue: ingredient?.quantity ?? 1)
        _unit = State(initialValue: ingredient?.unit ?? QuantityUnit.item.rawValue)
        _initialQuantity = State(initialValue: max(ingredient?.initialQuantity ?? 1, ingredient?.quantity ?? 1))
        _reorderThreshold = State(initialValue: ingredient?.reorderThreshold ?? 0)
        _category = State(initialValue: ingredient?.category ?? "Other")
        _expiryDate = State(initialValue: ingredient?.expiryDate ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
        _selectedLocation = State(initialValue: ingredient?.location ?? defaultLocation)
        _didSetCategory = State(initialValue: !isNew)
        _didSetExpiry = State(initialValue: !isNew)
        _didSetLocation = State(initialValue: !isNew || defaultLocation != nil)
        _didSetFullAmount = State(initialValue: !isNew)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    QuickNameField(prompt: "Name, or “500 g greek yogurt”", name: $name, quantity: $quantity, unit: $unit)
                        .onChange(of: name) { _, newValue in suggestDefaults(for: newValue) }
                    QuantityField("Amount", quantity: $quantity, unit: $unit)
                }

                Section {
                    Picker("Category", selection: Binding(get: { category }, set: { category = $0; didSetCategory = true })) {
                        ForEach(categories, id: \.self, content: Text.init)
                    }
                    Picker("Stored in", selection: Binding(get: { selectedLocation }, set: { selectedLocation = $0; didSetLocation = true })) {
                        Text("Unassigned").tag(nil as StorageLocation?)
                        ForEach(locations) { location in
                            Text(location.name).tag(location as StorageLocation?)
                        }
                    }
                    DatePicker("Expires", selection: Binding(get: { expiryDate }, set: { expiryDate = $0; didSetExpiry = true }), displayedComponents: .date)
                }

                Section {
                    QuantityField("Full amount", quantity: Binding(
                        get: { max(initialQuantity, quantity) },
                        set: { initialQuantity = $0; didSetFullAmount = true }
                    ), unit: .constant(unit), unitIsEditable: false)
                    QuantityField("Remind me below", quantity: $reorderThreshold, unit: .constant(unit), unitIsEditable: false)
                } header: {
                    Text("Running low")
                } footer: {
                    Text(reorderThreshold > 0
                         ? "When it drops below \(reorderThreshold.quantityText(unit: unit)), it's flagged as running low."
                         : "Leave at 0 to flag it when it's down to a fifth of the full amount.")
                }
            }
            .navigationTitle(ingredient == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: quantity) { _, newValue in
                if !didSetFullAmount { initialQuantity = newValue }
            }
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

    /// Category, shelf life and storage spot follow from the name ("milk" → Dairy, fridge,
    /// 10 days) until the user picks them.
    private func suggestDefaults(for name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let suggested = didSetCategory ? category : AisleClassifier.category(for: name)
        if !didSetCategory { category = suggested }
        if !didSetExpiry { expiryDate = ShelfLife.defaultExpiry(for: suggested) }
        if !didSetLocation { selectedLocation = ShelfLife.preferredLocation(for: suggested, in: locations) }
    }
}

struct GroceryFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let groceries: GroceryItem?
    @State private var name: String
    @State private var quantity: Double
    @State private var unit: String
    @State private var category: String
    @State private var note: String
    @State private var didPickCategory: Bool

    private let categories = CategoryStyle.all

    init(groceries: GroceryItem? = nil) {
        self.groceries = groceries
        _name = State(initialValue: groceries?.name ?? "")
        _quantity = State(initialValue: groceries?.quantity ?? 1)
        _unit = State(initialValue: groceries?.unit ?? QuantityUnit.item.rawValue)
        _category = State(initialValue: groceries?.category ?? "Other")
        _note = State(initialValue: groceries?.note ?? "")
        _didPickCategory = State(initialValue: groceries != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    QuickNameField(prompt: "Name, or “2 lb chicken thighs”", name: $name, quantity: $quantity, unit: $unit)
                        .onChange(of: name) { _, newValue in
                            // Suggest the aisle from the name until the user picks one themselves.
                            guard !didPickCategory else { return }
                            category = AisleClassifier.category(for: newValue)
                        }
                    QuantityField("Amount", quantity: $quantity, unit: $unit)
                }
                Section {
                    Picker("Aisle", selection: Binding(get: { category }, set: { category = $0; didPickCategory = true })) {
                        ForEach(categories, id: \.self, content: Text.init)
                    }
                    TextField("Note (brand, size…)", text: $note)
                }
            }
            .navigationTitle(groceries == nil ? "New Grocery Item" : "Edit Grocery Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        GroceryViewModel(modelContext: modelContext).saveGrocery(existing: groceries, name: name, quantity: quantity, unit: unit, category: category, note: note)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Quantity input

/// A name field that also understands a typed amount: "500 g greek yogurt" becomes
/// 500, g and "Greek yogurt" as soon as the user presses return or leaves the field.
struct QuickNameField: View {
    let prompt: String
    @Binding var name: String
    @Binding var quantity: Double
    @Binding var unit: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(prompt, text: $name)
            .focused($isFocused)
            .submitLabel(.next)
            .onSubmit(apply)
            .onChange(of: isFocused) { _, focused in if !focused { apply() } }
    }

    private func apply() {
        guard name.first?.isNumber == true || name.first.map({ "½¼¾⅓⅔⅛".contains($0) }) == true else { return }
        let parsed = IngredientLineParser.parse(name)
        guard !parsed.name.isEmpty, parsed.quantity > 0 else { return }
        withAnimation(.snappy) {
            quantity = parsed.quantity
            unit = parsed.unit
            name = parsed.name.prefix(1).uppercased() + parsed.name.dropFirst()
        }
    }
}

/// One control for an amount and its unit: type the number, nudge it with − and + in steps
/// that suit the unit, and change the unit from the menu right next to it.
struct QuantityField: View {
    private let title: String?
    @Binding private var quantity: Double
    @Binding private var unit: String
    private let unitIsEditable: Bool
    private let showsStepper: Bool

    @State private var settings = AppSettings.shared

    init(_ title: String? = nil, quantity: Binding<Double>, unit: Binding<String>, unitIsEditable: Bool = true, showsStepper: Bool = true) {
        self.title = title
        _quantity = quantity
        _unit = unit
        self.unitIsEditable = unitIsEditable
        self.showsStepper = showsStepper
    }

    var body: some View {
        if let title {
            LabeledContent(title) { controls }
        } else {
            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if showsStepper {
                nudgeButton("minus", label: "Decrease") { quantity = QuantityStep.stepped(quantity, unit: unit, up: false) }
                    .disabled(quantity <= 0)
            }
            TextField("0", value: $quantity, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(minWidth: 36, maxWidth: 72)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel(title ?? "Amount")
            unitControl
            if showsStepper {
                nudgeButton("plus", label: "Increase") { quantity = QuantityStep.stepped(quantity, unit: unit, up: true) }
            }
        }
        .sensoryFeedback(.selection, trigger: quantity)
    }

    @ViewBuilder
    private var unitControl: some View {
        let label = QuantityUnit.label(unit, quantity: quantity)
        if unitIsEditable {
            Menu {
                let layout = QuantityUnit.menuLayout(for: settings.unitSystem)
                ForEach(layout.sections, id: \.title) { group in
                    Section(group.title) { unitButtons(group.units) }
                }
                ForEach(layout.submenus, id: \.title) { group in
                    Menu(group.title) { unitButtons(group.units) }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(label)
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12), in: .capsule)
                .contentTransition(.numericText())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Unit, \(label)")
        } else {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .leading)
        }
    }

    private func unitButtons(_ units: [QuantityUnit]) -> some View {
        ForEach(units, id: \.self) { option in
            Button {
                unit = option.rawValue
            } label: {
                if option.rawValue == unit {
                    Label(option.menuName, systemImage: "checkmark")
                } else {
                    Text(option.menuName)
                }
            }
        }
    }

    private func nudgeButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 28, height: 28)
                .background(.fill.tertiary, in: .circle)
        }
        .buttonStyle(.borderless)
        .tint(.primary)
        .accessibilityLabel(label)
    }
}

/// How far − and + move an amount, by unit: whole items, tidy gram steps, quarter cups.
enum QuantityStep {
    static func step(for unit: String, quantity: Double) -> Double {
        switch QuantityUnit(rawValue: unit) {
        case .grams, .milliliters: quantity < 100 ? 10 : (quantity < 1000 ? 50 : 100)
        case .kilograms, .liters, .pounds, .cups: 0.25
        case .teaspoons, .tablespoons, .pints, .quarts, .gallons: 0.5
        case .ounces, .fluidOunces, .item, .dozen, .serving, .pinches, .dashes, .smidgens, nil: 1
        }
    }

    /// Moves to the next multiple of the step, so 237 g goes to 250, not 287.
    static func stepped(_ quantity: Double, unit: String, up: Bool) -> Double {
        let size = step(for: unit, quantity: up ? quantity : max(quantity - 0.0001, 0))
        let scaled = quantity / size
        let next = up ? (scaled + 1e-9).rounded(.down) + 1 : (scaled - 1e-9).rounded(.up) - 1
        return max(next * size, 0)
    }
}

extension QuantityUnit {
    struct Group { var title: String; var units: [QuantityUnit] }

    /// The unit menu: everyday units up top, the rest one level down so it stays short.
    static func menuLayout(for system: UnitSystem) -> (sections: [Group], submenus: [Group]) {
        let metric = system == .metric
        let sections = [
            Group(title: "Count", units: [.item, .dozen, .serving]),
            Group(title: "Weight", units: metric ? [.grams, .kilograms] : [.ounces, .pounds]),
            Group(title: "Volume", units: metric ? [.milliliters, .liters] : [.fluidOunces, .cups, .pints, .quarts, .gallons])
        ]
        let other = metric
            ? Group(title: "Imperial", units: [.ounces, .pounds, .fluidOunces, .pints, .quarts, .gallons])
            : Group(title: "Metric", units: [.grams, .kilograms, .milliliters, .liters])
        let kitchen = Group(title: "Cups & spoons", units: (metric ? [.cups] : []) + [.tablespoons, .teaspoons, .pinches, .dashes, .smidgens])
        return (sections, [kitchen, other])
    }

    /// Full name for the menu: "Grams (g)", "Items".
    var menuName: String {
        switch self {
        case .item: "Items"
        case .dozen: "Dozen"
        case .serving: "Servings"
        case .grams: "Grams (g)"
        case .kilograms: "Kilograms (kg)"
        case .milliliters: "Millilitres (ml)"
        case .liters: "Litres (L)"
        case .ounces: "Ounces (oz)"
        case .pounds: "Pounds (lb)"
        case .fluidOunces: "Fluid ounces (fl oz)"
        case .teaspoons: "Teaspoons (tsp)"
        case .tablespoons: "Tablespoons (tbsp)"
        case .cups: "Cups"
        case .pints: "Pints (pt)"
        case .quarts: "Quarts (qt)"
        case .gallons: "Gallons (gal)"
        case .pinches: "Pinches"
        case .dashes: "Dashes"
        case .smidgens: "Smidgens"
        }
    }

    /// Short label next to a number: "items", "item", "g", "cups".
    static func label(_ unit: String, quantity: Double) -> String {
        let plural = quantity != 1
        switch QuantityUnit(rawValue: unit) {
        case .item: return plural ? "items" : "item"
        case .serving: return plural ? "servings" : "serving"
        case .cups: return plural ? "cups" : "cup"
        case .pinches: return plural ? "pinches" : "pinch"
        case .dashes: return plural ? "dashes" : "dash"
        default: return unit
        }
    }
}

import SwiftData
import SwiftUI

struct InventoryDashboardView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case low = "Running Low"
        case expiring = "Expiring"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ingredient.expiryDate) private var ingredients: [Ingredient]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var showingSettings = false
    @State private var settings = AppSettings.shared
    @State private var notificationMessage: String?
    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var showingAddIngredient = false
    @State private var editingIngredient: Ingredient?
    @State private var feedbackTrigger = 0

    private var viewModel: InventoryViewModel { InventoryViewModel(modelContext: modelContext) }

    private var lowStock: [Ingredient] { ingredients.filter(InventoryViewModel.isLowStock) }
    private var expiring: [Ingredient] { ingredients.filter { viewModel.expiryState(for: $0.expiryDate) != .fresh } }

    private var visibleIngredients: [Ingredient] {
        let base: [Ingredient] = switch filter {
        case .all: ingredients
        case .low: lowStock
        case .expiring: expiring
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    GlassStatRow {
                        GlassStatTile(title: "Items", value: "\(ingredients.count)", symbol: "shippingbox.fill", tint: .blue)
                        GlassStatTile(title: "Running low", value: "\(lowStock.count)", symbol: "chart.bar.xaxis.ascending", tint: .orange)
                        GlassStatTile(title: "Expiring", value: "\(expiring.count)", symbol: "clock.badge.exclamationmark.fill", tint: .red)
                    }
                    Picker("Filter", selection: $filter.animation(.snappy)) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            useItUpSection

            if visibleIngredients.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groupedCategories, id: \.self) { category in
                    Section {
                        ForEach(grouped[category] ?? []) { ingredient in
                            row(for: ingredient)
                        }
                    } header: {
                        Label(category, systemImage: CategoryStyle.symbol(for: category))
                            .foregroundStyle(CategoryStyle.tint(for: category))
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: .blue) }
        .searchable(text: $searchText, prompt: "Search stock")
        .navigationTitle("Stock")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add low stock to Groceries", systemImage: "cart.badge.plus") {
                        GroceryViewModel(modelContext: modelContext).addLowStockIngredients(ingredients)
                        notificationMessage = "Low-stock items were added to your grocery list."
                    }
                    .disabled(lowStock.isEmpty)
                    Button("Schedule expiry alerts", systemImage: "bell.badge") {
                        scheduleExpiryAlerts()
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add item", systemImage: "plus") { showingAddIngredient = true }
                    .buttonStyle(.glassProminent)
            }
        }
        .sheet(isPresented: $showingAddIngredient) {
            IngredientFormView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .task(id: stockSignature) {
            await NotificationManager.shared.rescheduleIfAuthorized(for: ingredients, recipes: recipes)
        }
        .sheet(item: $editingIngredient) { ingredient in
            IngredientFormView(ingredient: ingredient, defaultLocation: ingredient.location)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTrigger)
        .alert("Stock", isPresented: Binding(
            get: { notificationMessage != nil },
            set: { if !$0 { notificationMessage = nil } }
        )) {
            Button("OK") { notificationMessage = nil }
        } message: {
            Text(notificationMessage ?? "")
        }
        .task {
            viewModel.checkAndAddLowStockToGroceries(ingredients)
        }
    }

    private var grouped: [String: [Ingredient]] {
        Dictionary(grouping: visibleIngredients, by: \.category)
    }

    private var stockSignature: Int {
        ingredients.reduce(into: Hasher()) { $0.combine($1.name); $0.combine($1.expiryDate); $0.combine($1.quantity) }.finalize()
    }

    @ViewBuilder
    private var useItUpSection: some View {
        let suggestions = UseItUpSuggester.suggestions(recipes: recipes, inventory: ingredients)
        if !suggestions.isEmpty, filter != .low {
            Section {
                ForEach(suggestions) { suggestion in
                    NavigationLink {
                        RecipeDetailView(recipe: suggestion.recipe)
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: "leaf.arrow.circlepath", tint: .green, size: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.recipe.name).font(.body.weight(.semibold))
                                Text("Uses \(suggestion.expiringIngredients.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if suggestion.missingCount == 0 {
                                StatusBadge(text: "Ready", symbol: "checkmark.circle.fill", tint: .green)
                            } else {
                                StatusBadge(text: "Missing \(suggestion.missingCount)", tint: .orange)
                            }
                        }
                    }
                }
            } header: {
                Label("Use it up", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.green)
            } footer: {
                Text("Your recipes that use what expires in the next few days.")
            }
        }
    }

    private var groupedCategories: [String] {
        grouped.keys.sorted()
    }

    @ViewBuilder
    private var emptyState: some View {
        if ingredients.isEmpty {
            ContentUnavailableView {
                Label("No stock yet", systemImage: "cart.badge.plus")
            } description: {
                Text("Add what's in your kitchen to track quantities and expiry dates.")
            } actions: {
                Button("Add Item") { showingAddIngredient = true }
                    .buttonStyle(.glassProminent)
            }
        } else if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView(
                filter == .low ? "Nothing running low" : "Nothing expiring soon",
                systemImage: "checkmark.seal.fill",
                description: Text("You're in good shape.")
            )
        }
    }

    private func row(for ingredient: Ingredient) -> some View {
        Button {
            editingIngredient = ingredient
        } label: {
            StockRow(ingredient: ingredient, state: viewModel.expiryState(for: ingredient.expiryDate))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Use one", systemImage: "minus") {
                viewModel.adjust(ingredient, by: -step(for: ingredient))
                feedbackTrigger += 1
            }
            .tint(.orange)
            Button("Add one", systemImage: "plus") {
                viewModel.adjust(ingredient, by: step(for: ingredient))
                feedbackTrigger += 1
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                viewModel.delete(ingredient)
            }
            Button("Refill", systemImage: "arrow.clockwise") {
                viewModel.refill(ingredient)
                feedbackTrigger += 1
            }
            .tint(.blue)
        }
        .contextMenu {
            Button("Use one", systemImage: "minus.circle") { viewModel.adjust(ingredient, by: -step(for: ingredient)) }
            Button("Add one", systemImage: "plus.circle") { viewModel.adjust(ingredient, by: step(for: ingredient)) }
            Button("Refill to \(ingredient.initialQuantity.quantityText(unit: ingredient.unit))", systemImage: "arrow.clockwise") {
                viewModel.refill(ingredient)
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { viewModel.delete(ingredient) }
        }
    }

    /// A sensible "one unit" nudge for each unit type (one item, 100 g, 250 ml…).
    private func step(for ingredient: Ingredient) -> Double {
        switch QuantityUnit(rawValue: ingredient.unit) {
        case .grams, .milliliters: 100
        case .kilograms, .liters: 0.25
        default: 1
        }
    }

    private func scheduleExpiryAlerts() {
        Task {
            do {
                let manager = NotificationManager.shared
                guard try await manager.requestAuthorization() else {
                    notificationMessage = "Notifications are disabled in Settings."
                    return
                }
                try await manager.scheduleExpiryNotifications(for: ingredients)
                notificationMessage = "Expiry alerts are scheduled."
            } catch {
                notificationMessage = "Could not schedule expiry alerts."
            }
        }
    }
}

private struct StockRow: View {
    let ingredient: Ingredient
    let state: InventoryViewModel.ExpiryState

    private var baseline: Double { max(ingredient.initialQuantity, ingredient.quantity, 0.0001) }
    private var level: Double { min(max(ingredient.quantity / baseline, 0), 1) }
    private var isLow: Bool { InventoryViewModel.isLowStock(ingredient) }

    var body: some View {
        HStack(spacing: 14) {
            IconTile(
                symbol: CategoryStyle.symbol(for: ingredient.category),
                tint: CategoryStyle.tint(for: ingredient.category)
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ingredient.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(ingredient.quantity.quantityText(unit: ingredient.unit))
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(isLow ? .orange : .secondary)
                        .contentTransition(.numericText(value: ingredient.quantity))
                }

                Gauge(value: level) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(isLow ? .orange : CategoryStyle.tint(for: ingredient.category))
                    .animation(.smooth, value: level)

                HStack(spacing: 6) {
                    if let location = ingredient.location {
                        Label(location.name, systemImage: location.icon)
                    }
                    Spacer()
                    expiryLabel
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe right to use or add, left to refill or delete.")
    }

    @ViewBuilder
    private var expiryLabel: some View {
        switch state {
        case .expired:
            StatusBadge(text: "Expired", symbol: "exclamationmark.triangle.fill", tint: .red)
        case .soon:
            StatusBadge(text: ingredient.expiryDate.formatted(.relative(presentation: .named)), symbol: "clock", tint: .orange)
        case .fresh:
            Text(ingredient.expiryDate, format: .dateTime.month(.abbreviated).day())
        }
    }
}

#Preview {
    NavigationStack { InventoryDashboardView() }
        .modelContainer(for: [Ingredient.self, StorageLocation.self, GroceryItem.self], inMemory: true)
}

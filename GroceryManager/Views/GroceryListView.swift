import SwiftData
import SwiftUI

struct GroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var groceries: [GroceryItem]
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]
    @Query(sort: \MealPlanEntry.date) private var allEntries: [MealPlanEntry]
    @State private var showingAddGrocery = false
    @State private var showingRecipePicker = false
    @State private var showingSettings = false
    @State private var selectedRecipe: Recipe?
    @State private var toast: String?
    @State private var settings = AppSettings.shared
    @State private var entitlements = EntitlementService.shared
    @State private var pricedList: PricedList?
    @State private var checkoutURL: URL?
    @Environment(\.openURL) private var openURL

    private var viewModel: GroceryViewModel { GroceryViewModel(modelContext: modelContext) }

    private var pendingLines: [PlannedGroceryLine] {
        pending.map { PlannedGroceryLine(name: $0.name, quantity: $0.quantity, unit: $0.unit, category: $0.category) }
    }

    private var priceSignature: String {
        "\(entitlements.isPlus)|\(settings.region.rawValue)|" + pending.map { "\($0.name):\($0.quantity)\($0.unit)" }.joined(separator: ",")
    }

    private var checkedGroceries: [GroceryItem] { groceries.filter(\.isChecked) }
    private var pending: [GroceryItem] { groceries.filter { !$0.isChecked } }

    /// Aisle order, unchecked first, then by name.
    private var sortedGroceries: [GroceryItem] {
        groceries.sorted { lhs, rhs in
            let l = AisleClassifier.aisleIndex(for: lhs.category), r = AisleClassifier.aisleIndex(for: rhs.category)
            if l != r { return l < r }
            if lhs.isChecked != rhs.isChecked { return !lhs.isChecked }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var groupedGroceries: [String: [GroceryItem]] {
        Dictionary(grouping: sortedGroceries, by: \.category)
    }

    private var sortedCategories: [String] {
        groupedGroceries.keys.sorted { AisleClassifier.aisleIndex(for: $0) < AisleClassifier.aisleIndex(for: $1) }
    }

    private var estimatedTotalCents: Int {
        pending.reduce(0) { $0 + $1.priceCents }
    }

    var body: some View {
        List {
            Section {
                GlassStatRow {
                    GlassStatTile(title: "To buy", value: "\(pending.count)", symbol: "cart.fill", tint: .pink)
                    GlassStatTile(title: "In basket", value: "\(checkedGroceries.count)", symbol: "basket.fill", tint: .green)
                    if entitlements.hasFeature(.priceAwareShopping) {
                        GlassStatTile(
                            title: settings.weeklyBudgetCents > 0 ? "Of \(settings.formatPrice(cents: settings.weeklyBudgetCents))" : "Estimate",
                            value: estimatedTotalCents > 0 ? settings.formatPrice(cents: estimatedTotalCents) : "—",
                            symbol: "dollarsign.circle.fill",
                            tint: settings.weeklyBudgetCents > 0 && estimatedTotalCents > settings.weeklyBudgetCents ? .orange : .purple
                        )
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                if entitlements.hasFeature(.priceAwareShopping), settings.weeklyBudgetCents > 0, estimatedTotalCents > settings.weeklyBudgetCents {
                    budgetCard
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                if !checkedGroceries.isEmpty {
                    Button {
                        let count = checkedGroceries.count
                        viewModel.clearChecked(groceries)
                        withAnimation { toast = settings.autoStockOnCheck ? "Cleared \(count) — they're in your stock" : "Cleared \(count) bought item\(count == 1 ? "" : "s")" }
                    } label: {
                        Label("Clear \(checkedGroceries.count) bought item\(checkedGroceries.count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.green)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if !entitlements.hasFeature(.priceAwareShopping), !groceries.isEmpty {
                    LockedFeatureCard(feature: .priceAwareShopping)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }

            if groceries.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Your list is empty", systemImage: "cart")
                    } description: {
                        Text(settings.autoBuildGroceryList
                             ? "Plan meals and everything you're missing shows up here, sorted by aisle."
                             : "Add items, or send missing ingredients here from the Meal Plan or a recipe.")
                    } actions: {
                        Button("Add Item") { showingAddGrocery = true }
                            .buttonStyle(.glassProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(sortedCategories, id: \.self) { category in
                    Section {
                        ForEach(groupedGroceries[category] ?? []) { grocery in
                            GroceryRow(grocery: grocery, unitSystem: settings.unitSystem, showPrice: entitlements.hasFeature(.priceAwareShopping)) { checked in
                                viewModel.setChecked(grocery, checked, inventory: inventory, locations: locations, autoStock: settings.autoStockOnCheck)
                                if checked, settings.autoStockOnCheck {
                                    withAnimation { toast = "\(grocery.name) added to \(ShelfLife.preferredLocation(for: grocery.category, in: locations)?.name ?? "stock")" }
                                }
                            }
                        }
                        .onDelete { offsets in
                            let categoryGroceries = groupedGroceries[category] ?? []
                            offsets.map { categoryGroceries[$0] }.forEach(viewModel.delete)
                        }
                    } header: {
                        Label(category, systemImage: CategoryStyle.symbol(for: category))
                            .foregroundStyle(CategoryStyle.tint(for: category))
                    }
                }
            }
        }
        .navigationTitle("Groceries")
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: .pink) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add from recipe", systemImage: "book") { showingRecipePicker = true }
                    Button("Rebuild from this week's plan", systemImage: "arrow.clockwise") { rebuild() }
                    Button("Add low stock items", systemImage: "chart.bar.xaxis.ascending") {
                        viewModel.addLowStockIngredients(inventory)
                        withAnimation { toast = "Low stock items added" }
                    }
                    Divider()
                    if entitlements.hasFeature(.checkoutLinks) {
                        Menu {
                            ForEach(CheckoutProvider.available(in: settings.region)) { provider in
                                Button(provider.name, systemImage: provider.symbol) { sendToCheckout(provider) }
                            }
                        } label: {
                            Label("Send list to…", systemImage: "shippingbox")
                        }
                        .disabled(pending.isEmpty)
                    } else {
                        PlusGate(feature: .checkoutLinks, action: {}) {
                            Label("Send list to a delivery service", systemImage: "shippingbox")
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add grocery", systemImage: "plus") { showingAddGrocery = true }
                    .buttonStyle(.glassProminent)
            }
        }
        .sheet(isPresented: $showingAddGrocery) {
            GroceryFormView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingRecipePicker) {
            RecipePickerView(selectedRecipe: $selectedRecipe) { recipe in
                viewModel.addMissingRecipeIngredients(recipe.ingredients, inventory: inventory)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation { self.toast = nil }
                    }
            }
        }
        .task(id: priceSignature) {
            guard entitlements.hasFeature(.priceAwareShopping), !pending.isEmpty else { return }
            pricedList = await PriceService.apply(to: groceries, region: settings.region)
            try? modelContext.save()
        }
    }

    /// Budget mode: shows how far over the list is and which lines cost the most.
    private var budgetCard: some View {
        let over = estimatedTotalCents - settings.weeklyBudgetCents
        let costly = pending.filter { $0.priceCents > 0 }.sorted { $0.priceCents > $1.priceCents }.prefix(3)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                IconTile(symbol: "chart.line.downtrend.xyaxis", tint: .orange, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(settings.formatPrice(cents: over)) over your weekly budget").font(.subheadline.weight(.semibold))
                    Text("Biggest lines: \(costly.map { "\($0.name) \(settings.formatPrice(cents: $0.priceCents))" }.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Text("Swap a pricey dinner with Plan my week, or check what's on sale (marked in the list).")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .glassCard(cornerRadius: 22, tint: .orange)
    }

    private func sendToCheckout(_ provider: CheckoutProvider) {
        Task {
            if let url = await CheckoutService.checkoutURL(provider: provider, lines: pendingLines, region: settings.region) {
                openURL(url)
            } else {
                withAnimation { toast = "Couldn't build a link for \(provider.name)" }
            }
        }
    }

    private func rebuild() {
        let weekStart = Date.now.weekStart
        let end = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let entries = allEntries.filter { $0.date >= weekStart && $0.date < end }
        let result = GroceryListBuilder().sync(weekStart: weekStart, entries: entries, inventory: inventory, modelContext: modelContext)
        withAnimation {
            toast = result.isEmpty ? "List already matches the plan" : "Added \(result.added), updated \(result.updated), removed \(result.removed)"
        }
    }
}

private struct GroceryRow: View {
    let grocery: GroceryItem
    let unitSystem: UnitSystem
    let showPrice: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggle(!grocery.isChecked)
            } label: {
                Image(systemName: grocery.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(grocery.isChecked ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: grocery.isChecked)

            VStack(alignment: .leading, spacing: 4) {
                Text(grocery.name)
                    .font(.headline)
                    .strikethrough(grocery.isChecked)
                    .foregroundStyle(grocery.isChecked ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text(UnitConverter.displayText(grocery.quantity, unit: grocery.unit, system: unitSystem))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if grocery.source == "plan" {
                        StatusBadge(text: "From plan", symbol: "calendar", tint: .indigo)
                    } else if grocery.source == "lowstock" {
                        StatusBadge(text: "Running low", symbol: "chart.bar.xaxis.ascending", tint: .orange)
                    }
                    if !grocery.note.isEmpty {
                        Text(grocery.note).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }

            Spacer()

            if showPrice, grocery.priceCents > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(AppSettings.shared.formatPrice(cents: grocery.priceCents, currency: grocery.currencyCode.isEmpty ? nil : grocery.currencyCode))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !grocery.storeName.isEmpty {
                        Text(grocery.storeName).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }

            NavigationLink(destination: GroceryFormView(groceries: grocery)) {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecipePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    @Binding var selectedRecipe: Recipe?
    let onSelect: (Recipe) -> Void

    var body: some View {
        NavigationStack {
            List {
                if recipes.isEmpty {
                    ContentUnavailableView("No recipes", systemImage: "book", description: Text("Create a recipe first to add its ingredients to your grocery list."))
                } else {
                    ForEach(recipes) { recipe in
                        Button {
                            selectedRecipe = recipe
                            onSelect(recipe)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recipe.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(recipe.ingredients.count) ingredients")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Select Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

import SwiftData
import SwiftUI

enum LocationShelfLayout {
    static let itemsPerShelf = 2

    static func rows(for ingredients: [Ingredient]) -> [[Ingredient?]] {
        let sortedIngredients = ingredients.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        var rows: [[Ingredient?]] = []
        var currentRow: [Ingredient?] = []

        for ingredient in sortedIngredients {
            currentRow.append(ingredient)
            if currentRow.count == itemsPerShelf {
                rows.append(currentRow)
                currentRow = []
            }
        }

        if !currentRow.isEmpty {
            while currentRow.count < itemsPerShelf {
                currentRow.append(nil)
            }
            rows.append(currentRow)
        }

        // An empty location shows one row of placeholder slots; otherwise every item is shown.
        if rows.isEmpty {
            rows.append(Array(repeating: nil, count: itemsPerShelf))
        }

        return rows
    }
}

struct LocationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]
    @State private var showingAddLocation = false

    private var unassignedIngredients: [Ingredient] {
        ingredients.filter { $0.location == nil }
    }

    var body: some View {
        ScrollView {
            Group {
            if locations.isEmpty && unassignedIngredients.isEmpty {
                ContentUnavailableView("No storage locations", systemImage: "archivebox", description: Text("Create a fridge, pantry, or cabinet to organize groceries."))
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                // Masonry: each column stacks independently so a short card
                // (e.g. a freezer with two items) doesn't leave a row-sized gap.
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(masonryColumns.enumerated()), id: \.offset) { index, column in
                        VStack(spacing: 16) {
                            ForEach(column) { location in
                                locationLink(for: location)
                            }
                            if index == unassignedColumnIndex && !unassignedIngredients.isEmpty {
                                unassignedSection
                            }
                        }
                        // Keep cards at their natural height; otherwise the shorter
                        // column's cards stretch to match the taller column.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
            }
            .padding()
        }
        .background { AmbientBackground(tint: .teal) }
        .navigationTitle("Storage")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddLocation = true
                } label: {
                    Label("Add storage location", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
            }
        }
        .sheet(isPresented: $showingAddLocation) {
            LocationFormView()
        }
    }

    /// Splits locations into `gridColumnCount` columns, always adding the next
    /// card to the column with the least estimated height.
    private var masonryColumns: [[StorageLocation]] {
        var columns = Array(repeating: [StorageLocation](), count: gridColumnCount)
        var heights = Array(repeating: 0, count: gridColumnCount)
        for location in locations {
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[target].append(location)
            // Header plus one row per two items (empty slot counts as an item).
            heights[target] += 1 + (location.ingredients.count + 2) / 2
        }
        return columns
    }

    /// The unassigned list goes at the bottom of the shortest column.
    private var unassignedColumnIndex: Int {
        let columns = masonryColumns
        let heights = columns.map { $0.reduce(0) { $0 + 1 + ($1.ingredients.count + 2) / 2 } }
        return heights.indices.min { heights[$0] < heights[$1] } ?? 0
    }

    private func locationLink(for location: StorageLocation) -> some View {
        NavigationLink {
            LocationDetailView(location: location)
        } label: {
            locationTile(for: location)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                modelContext.delete(location)
                try? modelContext.save()
            }
        }
    }

    private var unassignedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unassigned")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(unassignedIngredients) { ingredient in
                NavigationLink {
                    IngredientFormView(ingredient: ingredient)
                } label: {
                    HStack {
                        Image(systemName: "questionmark.folder")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(ingredient.name)
                            Text(ingredient.quantity.quantityText(unit: ingredient.unit))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var gridColumnCount: Int {
        #if os(iOS)
        return horizontalSizeClass == .regular ? 2 : 1
        #else
        return 1
        #endif
    }

    @ViewBuilder
    private func locationTile(for location: StorageLocation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                IconTile(symbol: location.icon, tint: .teal, size: 32)
                Text(location.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(location.ingredients.count.counted("item"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let shelves = LocationShelfLayout.rows(for: location.ingredients)

            VStack(spacing: 8) {
                ForEach(shelves.indices, id: \.self) { rowIndex in
                    let rowItems = shelves[rowIndex]

                    HStack(spacing: 8) {
                        ForEach(0..<LocationShelfLayout.itemsPerShelf, id: \.self) { itemIndex in
                            if itemIndex < rowItems.count, let ingredient = rowItems[itemIndex] {
                                shelfItemView(for: ingredient)
                            } else {
                                emptyShelfSlot()
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
    }

    private func shelfItemView(for ingredient: Ingredient) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: CategoryStyle.symbol(for: ingredient.category))
                    .font(.caption2)
                    .foregroundStyle(CategoryStyle.tint(for: ingredient.category))
                Text(ingredient.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text(ingredient.quantity.quantityText(unit: ingredient.unit))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 14))
    }

    private func emptyShelfSlot() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.clear)
            .frame(maxWidth: .infinity, minHeight: 58)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(.secondary.opacity(0.5))
            )
    }
}

struct LocationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let location: StorageLocation
    @State private var showingAddIngredient = false
    @State private var showingEditLocation = false

    var body: some View {
        List {
            if location.ingredients.isEmpty {
                ContentUnavailableView("Location is empty", systemImage: "cart.badge.plus", description: Text("Add an ingredient to start tracking stock."))
            } else {
                ForEach(location.ingredients.sorted { $0.name < $1.name }) { ingredient in
                    NavigationLink {
                        IngredientFormView(ingredient: ingredient, defaultLocation: location)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ingredient.name)
                            Text("\(ingredient.quantity.quantityText) \(ingredient.unit) · expires \(ingredient.expiryDate, format: .dateTime.month(.abbreviated).day().year())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { location.ingredients.sorted { $0.name < $1.name }[$0] }.forEach { ingredient in
                        modelContext.delete(ingredient)
                    }
                    try? modelContext.save()
                }
            }
        }
        .navigationTitle(location.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingEditLocation = true
                } label: {
                    Label("Edit storage location", systemImage: "pencil")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddIngredient = true
                } label: {
                    Label("Add ingredient", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddIngredient) {
            IngredientFormView(defaultLocation: location)
        }
        .sheet(isPresented: $showingEditLocation) {
            LocationFormView(location: location)
        }
    }
}

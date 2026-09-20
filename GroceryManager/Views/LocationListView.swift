import SwiftData
import SwiftUI

enum LocationShelfLayout {
    static let shelfCount = 3
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

        while rows.count < shelfCount {
            rows.append(Array(repeating: nil, count: itemsPerShelf))
        }

        return Array(rows.prefix(shelfCount))
    }
}

struct LocationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]
    @State private var showingAddLocation = false

    private var unassignedIngredients: [Ingredient] {
        ingredients.filter { $0.location == nil }
    }

    private func categoryIcon(for ingredient: Ingredient) -> String {
        switch ingredient.category.lowercased() {
        case "dairy":
            return "drop.fill"
        case "produce", "fruit", "vegetable":
            return "leaf.fill"
        case "meat", "protein":
            return "fork.knife"
        case "bakery", "grain", "pantry":
            return "basket.fill"
        case "seafood":
            return "fish.fill"
        default:
            return "tag.fill"
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: gridColumnCount), spacing: 16) {
                if locations.isEmpty && unassignedIngredients.isEmpty {
                    ContentUnavailableView("No storage locations", systemImage: "archivebox", description: Text("Create a fridge, pantry, or cabinet to organize groceries."))
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .gridCellColumns(1)
                        .gridCellUnsizedAxes(.horizontal)
                } else {
                    ForEach(locations) { location in
                        NavigationLink {
                            LocationDetailView(location: location)
                        } label: {
                            locationTile(for: location)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                modelContext.delete(location)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    if !unassignedIngredients.isEmpty {
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
                                            Text("\(ingredient.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .gridCellColumns(1)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Storage")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddLocation = true
                } label: {
                    Label("Add storage location", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddLocation) {
            LocationFormView()
        }
    }

    private var gridColumnCount: Int {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? 2 : 1
        #else
        return 1
        #endif
    }

    @ViewBuilder
    private func locationTile(for location: StorageLocation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Image(systemName: location.icon)
                    .font(.headline)
                    .foregroundStyle(.tint)
                Text(location.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(location.ingredients.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let shelves = LocationShelfLayout.rows(for: location.ingredients)

            VStack(spacing: 8) {
                ForEach(0..<LocationShelfLayout.shelfCount, id: \.self) { rowIndex in
                    let rowItems = shelves.indices.contains(rowIndex) ? shelves[rowIndex] : Array(repeating: nil as Ingredient?, count: LocationShelfLayout.itemsPerShelf)

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
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private func shelfItemView(for ingredient: Ingredient) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: categoryIcon(for: ingredient))
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text(ingredient.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text("\(ingredient.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
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
                            Text("\(ingredient.quantity.formatted(.number.precision(.fractionLength(0...2)))) · expires \(ingredient.expiryDate, format: .dateTime.month(.abbreviated).day().year())")
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

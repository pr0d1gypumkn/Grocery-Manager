import SwiftData
import SwiftUI

struct LocationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]
    @State private var showingAddLocation = false

    private var unassignedIngredients: [Ingredient] {
        ingredients.filter { $0.location == nil }
    }

    var body: some View {
        List {
            if locations.isEmpty && unassignedIngredients.isEmpty {
                ContentUnavailableView("No storage locations", systemImage: "archivebox", description: Text("Create a fridge, pantry, or cabinet to organize groceries."))
            } else {
                ForEach(locations) { location in
                    NavigationLink {
                        LocationDetailView(location: location)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(location.name)
                                Text("\(location.ingredients.count) items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: location.icon)
                                .foregroundStyle(.tint)
                        }
                    }
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
                    Section("Unassigned") {
                        ForEach(unassignedIngredients) { ingredient in
                            NavigationLink {
                                IngredientFormView(ingredient: ingredient)
                            } label: {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(ingredient.name)
                                        Text("\(ingredient.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "questionmark.folder")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { unassignedIngredients[$0] }.forEach { ingredient in
                                modelContext.delete(ingredient)
                            }
                            try? modelContext.save()
                        }
                    }
                }
            }
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

import SwiftData
import SwiftUI

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var showingAddRecipe = false
    @State private var showingImportRecipe = false

    var body: some View {
        List {
            if recipes.isEmpty {
                ContentUnavailableView("No recipes", systemImage: "book", description: Text("Create a recipe and add its required ingredients."))
            } else {
                ForEach(recipes) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.name)
                                .font(.headline)
                            Text("\(recipe.ingredients.count) required ingredients")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { recipes[$0] }.forEach { recipe in
                        RecipeViewModel(modelContext: modelContext).delete(recipe)
                    }
                }
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingAddRecipe = true
                    } label: {
                        Label("Create recipe", systemImage: "square.and.pencil")
                    }
                    Button {
                        showingImportRecipe = true
                    } label: {
                        Label("Parse note or URL", systemImage: "apple.intelligence")
                    }
                } label: {
                    Label("Recipe actions", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRecipe) {
            RecipeFormView()
        }
        .sheet(isPresented: $showingImportRecipe) {
            RecipeImportView()
        }
    }
}

struct RecipeImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var sourceKind = SourceKind.note
    @State private var sourceText = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

    private enum SourceKind: String, CaseIterable {
        case note = "Note"
        case url = "URL"
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Source", selection: $sourceKind) {
                    ForEach(SourceKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                Section {
                    if sourceKind == .note {
                        TextEditor(text: $sourceText)
                            .frame(minHeight: 220)
                    } else {
                        TextField("https://example.com/recipe", text: $sourceText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text(sourceKind == .note ? "Recipe note" : "Recipe URL")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Import Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        importRecipe()
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Text("Parse")
                        }
                    }
                    .disabled(isImporting || sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func importRecipe() {
        isImporting = true
        errorMessage = nil

        let source: RecipeImportSource
        if sourceKind == .note {
            source = .note(sourceText)
        } else if let url = URL(string: sourceText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            source = .url(url)
        } else {
            errorMessage = RecipeImportError.invalidURL.localizedDescription
            isImporting = false
            return
        }

        Task {
            do {
                let draft = try await OnDeviceRecipeImporter().importRecipe(from: source)
                RecipeViewModel(modelContext: modelContext).saveRecipe(
                    existing: nil,
                    name: draft.name,
                    instructions: draft.instructions,
                    ingredients: draft.ingredients
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}

struct RecipeDetailView: View {
    let recipe: Recipe
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @State private var showingEditRecipe = false

    private var pantryMatches: [PantryMatch] {
        PantryMatcher().matches(recipeIngredients: recipe.ingredients, inventory: inventory)
    }

    var body: some View {
        List {
            if !recipe.instructions.isEmpty {
                Section("Instructions") {
                    Text(recipe.instructions)
                }
            }

            Section("Required ingredients") {
                if recipe.ingredients.isEmpty {
                    Text("No ingredients added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recipe.ingredients) { ingredient in
                        LabeledContent(
                            ingredient.name,
                            value: "\(ingredient.requiredQuantity.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit)"
                        )
                    }
                }
            }

            Section("In Stock") {
                let matches = pantryMatches.filter(\.isInStock)
                if matches.isEmpty {
                    Text("Nothing fully stocked")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matches) { match in
                        PantryMatchRow(match: match, isMissing: false)
                    }
                }
            }

            Section("Need to Buy") {
                let matches = pantryMatches.filter { !$0.isInStock }
                if matches.isEmpty {
                    Label("Everything is in stock", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(matches) { match in
                        PantryMatchRow(match: match, isMissing: true)
                    }
                }
            }
        }
        .navigationTitle(recipe.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditRecipe = true
                } label: {
                    Label("Edit recipe", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditRecipe) {
            RecipeFormView(recipe: recipe)
        }
    }
}

private struct PantryMatchRow: View {
    let match: PantryMatch
    let isMissing: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: isMissing ? "cart.badge.plus" : "checkmark.circle.fill")
                        .foregroundStyle(isMissing ? .orange : .green)
                    Text(match.requiredName)
                    Spacer()
                    Text(quantityLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                    .tint(isMissing ? .orange : .green)
            }
        }
    }

    private var progress: Double {
        guard match.requiredQuantity > 0 else { return 1 }
        return min(match.availableQuantity / match.requiredQuantity, 1)
    }

    private var quantityLabel: String {
        if isMissing {
            return "Buy \(match.missingQuantity.formatted(.number.precision(.fractionLength(0...2)))) \(match.unit)"
        }
        return "Have \(match.availableQuantity.formatted(.number.precision(.fractionLength(0...2)))) \(match.unit)"
    }
}

struct RecipeFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let recipe: Recipe?
    @State private var name: String
    @State private var instructions: String
    @State private var ingredients: [DraftRecipeIngredient]

    init(recipe: Recipe? = nil) {
        self.recipe = recipe
        _name = State(initialValue: recipe?.name ?? "")
        _instructions = State(initialValue: recipe?.instructions ?? "")
        _ingredients = State(initialValue: recipe?.ingredients.map {
            DraftRecipeIngredient(name: $0.name, quantity: $0.requiredQuantity, unit: $0.unit)
        } ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Name", text: $name)
                    TextField("Instructions", text: $instructions, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section {
                    if ingredients.isEmpty {
                        Text("Add the ingredients this recipe requires.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($ingredients) { $ingredient in
                            HStack {
                                TextField("Ingredient", text: $ingredient.name)
                                Stepper(value: $ingredient.quantity, in: 0...999, step: 0.5) {
                                    Text(ingredient.quantity.formatted(.number.precision(.fractionLength(0...2))))
                                        .frame(minWidth: 32)
                                }
                            }
                            Picker("Unit", selection: $ingredient.unit) {
                                ForEach(QuantityUnit.allCases, id: \.self) { unit in
                                    Text(unit.rawValue).tag(unit.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .onDelete { ingredients.remove(atOffsets: $0) }
                    }

                    Button {
                        ingredients.append(DraftRecipeIngredient(name: "", quantity: 1, unit: "item"))
                    } label: {
                        Label("Add required ingredient", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Required ingredients")
                }
            }
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        RecipeViewModel(modelContext: modelContext).saveRecipe(
                            existing: recipe,
                            name: name,
                            instructions: instructions,
                            ingredients: ingredients
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

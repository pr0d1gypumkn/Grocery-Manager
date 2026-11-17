import AppIntents
import PhotosUI
import SwiftData
import SwiftUI

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @State private var showingAddRecipe = false
    @State private var showingImportRecipe = false
    @State private var planContext: AddMealContext?
    @State private var searchText = ""
    @State private var suggestions: [RecipeSuggestion] = []
    @State private var entitlements = EntitlementService.shared
    @State private var settings = AppSettings.shared

    private var filteredRecipes: [Recipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return recipes }
        return recipes.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        List {
            if recipes.isEmpty {
                ContentUnavailableView {
                    Label("No recipes", systemImage: "book.closed")
                } description: {
                    Text("Create a recipe or import one from a note or website.")
                } actions: {
                    Button("New Recipe") { showingAddRecipe = true }
                        .buttonStyle(.glassProminent)
                    Button("Import") { showingImportRecipe = true }
                        .buttonStyle(.glass)
                }
                .listRowBackground(Color.clear)
            } else if filteredRecipes.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            } else {
                if searchText.isEmpty { ideasSection }
                ForEach(filteredRecipes) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        RecipeRow(recipe: recipe, inventory: inventory)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Plan", systemImage: "calendar.badge.plus") {
                            planContext = AddMealContext(date: .now, mealType: .dinner, recipe: recipe)
                        }
                        .tint(.indigo)
                    }
                    .contextMenu {
                        Button("Add to meal plan", systemImage: "calendar.badge.plus") {
                            planContext = AddMealContext(date: .now, mealType: .dinner, recipe: recipe)
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            RecipeViewModel(modelContext: modelContext).delete(recipe)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { filteredRecipes[$0] }.forEach { recipe in
                        RecipeViewModel(modelContext: modelContext).delete(recipe)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: .orange) }
        .searchable(text: $searchText, prompt: "Recipes or ingredients")
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import recipe", systemImage: "apple.intelligence") {
                    showingImportRecipe = true
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Create recipe", systemImage: "plus") {
                    showingAddRecipe = true
                }
                .buttonStyle(.glassProminent)
            }
        }
        .sheet(isPresented: $showingAddRecipe) {
            RecipeFormView()
        }
        .sheet(isPresented: $showingImportRecipe) {
            RecipeImportView()
        }
        .sheet(item: $planContext) { context in
            AddMealView(date: context.date, mealType: context.mealType, recipe: context.recipe)
        }
        .task(id: "\(recipes.count)-\(entitlements.isPlus)") {
            guard entitlements.hasFeature(.recipeSuggestions) else { suggestions = []; return }
            suggestions = await SuggestionService.suggestions(savedRecipes: recipes, pantry: inventory, dietTags: settings.dietTags, limit: 4)
        }
    }

    @ViewBuilder
    private var ideasSection: some View {
        if entitlements.hasFeature(.recipeSuggestions) {
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { suggestion in
                        HStack(spacing: 12) {
                            IconTile(symbol: "sparkles", tint: .purple, size: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.name).font(.body.weight(.semibold))
                                Text((suggestion.reasons.isEmpty ? [suggestion.tags.joined(separator: ", ")] : suggestion.reasons).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Button("Save") {
                                RecipeViewModel(modelContext: modelContext).save(draft: suggestion.draft)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                } header: {
                    Label("Ideas for you", systemImage: "sparkles").foregroundStyle(.purple)
                } footer: {
                    Text("Recipes you haven't saved, matched to your tastes and what's in the pantry.")
                }
            }
        } else {
            Section {
                LockedFeatureCard(feature: .recipeSuggestions)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe
    let inventory: [Ingredient]

    private var subtitle: String {
        var parts = ["\(recipe.ingredients.count) ingredients", "serves \(recipe.servings)"]
        if recipe.totalMinutes > 0 { parts.append("\(recipe.totalMinutes) min") }
        if let facts = recipe.nutritionPerServing { parts.append("\(Int(facts.calories.rounded())) kcal") }
        return parts.joined(separator: " · ")
    }

    private var missingCount: Int {
        PantryMatcher()
            .matches(recipeIngredients: recipe.ingredients, inventory: inventory)
            .filter { !$0.isInStock }
            .count
    }

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "fork.knife", tint: .orange, size: 42)
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if recipe.ingredients.isEmpty {
                        EmptyView()
                    } else if missingCount == 0 {
                        StatusBadge(text: "Ready", symbol: "checkmark.circle.fill", tint: .green)
                    } else {
                        StatusBadge(text: "Missing \(missingCount)", tint: .orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct RecipeSnippetView: View {
    // Pass the fetched entities directly from the Intent
    let recipes: [RecipeEntity]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recipes.isEmpty {
                Label("No recipes found.", systemImage: "book")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                // Use a standard VStack or ForEach instead of a List/NavigationLink
                ForEach(recipes, id: \.id) { recipe in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.name) // Use whatever display properties are on your Entity
                            .font(.headline)
                        
                        Divider()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
    }
}

struct RecipeImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var sourceKind = SourceKind.note
    @State private var sourceText = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var entitlements = EntitlementService.shared
    @State private var showingPaywall = false

    private enum SourceKind: String, CaseIterable {
        case note = "Note"
        case url = "Website"
        case social = "Social"
        case photo = "Photo"
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
                    switch sourceKind {
                    case .note:
                        TextEditor(text: $sourceText)
                            .frame(minHeight: 220)
                    case .url, .social:
                        TextField(sourceKind == .url ? "https://example.com/recipe" : "TikTok, Instagram or YouTube link", text: $sourceText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    case .photo:
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(photo == nil ? "Choose a photo or screenshot" : "Choose a different photo", systemImage: "photo.on.rectangle")
                        }
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 220).clipShape(.rect(cornerRadius: 12))
                        }
                    }
                } header: {
                    Text(sourceKind.rawValue)
                } footer: {
                    Text(footerText)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                if !entitlements.hasFeature(.socialImport) {
                    Section {
                        LockedFeatureCard(feature: .socialImport)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) { photo = UIImage(data: data) }
                }
            }
            .onChange(of: sourceKind) { _, kind in
                if (kind == .social || kind == .photo), !entitlements.hasFeature(.socialImport) {
                    showingPaywall = true
                    sourceKind = .note
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView(feature: .socialImport) }
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
                    .disabled(isImporting || !canImport)
                }
            }
        }
    }

    private var canImport: Bool {
        sourceKind == .photo ? photo != nil : !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var footerText: String {
        switch sourceKind {
        case .note: "Paste any recipe text. Parsed on-device with Apple Intelligence."
        case .url: "Works with any site that publishes standard recipe markup, and falls back to on-device parsing."
        case .social: "Reads the post's embedded recipe or caption. Platforms without partner access fall back to the caption and on-device parsing."
        case .photo: "Screenshots, cookbook pages and handwritten cards are read on-device with Vision, then parsed."
        }
    }

    private func importRecipe() {
        isImporting = true
        errorMessage = nil

        Task {
            do {
                let draft: ImportedRecipeDraft
                switch sourceKind {
                case .note:
                    draft = try await OnDeviceRecipeImporter().importRecipe(from: .note(sourceText))
                case .url, .social:
                    let value = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                    guard let url = URL(string: value.hasPrefix("http") ? value : "https://\(value)") else { throw RecipeImportError.invalidURL }
                    if sourceKind == .social || SocialRecipeImporter.isSocialURL(url) {
                        draft = try await SocialRecipeImporter().importRecipe(from: url)
                    } else {
                        draft = try await RecipeWebImporter().importRecipe(from: url)
                    }
                case .photo:
                    guard let photo else { throw RecipeImportError.emptySource }
                    draft = try await PhotoRecipeImporter().importRecipe(from: photo)
                }
                RecipeViewModel(modelContext: modelContext).save(draft: draft)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let recipe: Recipe
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @State private var servings: Int
    @State private var showingEditRecipe = false
    @State private var planContext: AddMealContext?
    @State private var addedCount: Int?

    init(recipe: Recipe, servings: Int? = nil) {
        self.recipe = recipe
        _servings = State(initialValue: servings ?? recipe.servings)
    }

    private var scale: Double {
        recipe.servings > 0 ? Double(servings) / Double(recipe.servings) : 1
    }

    private var scaledRequirements: [IngredientRequirement] {
        recipe.ingredients.map {
            IngredientRequirement(name: $0.name, quantity: $0.requiredQuantity * scale, unit: $0.unit)
        }
    }

    private var pantryMatches: [PantryMatch] {
        PantryMatcher().matches(requirements: scaledRequirements, inventory: inventory)
    }

    private var missingIngredients: [PantryMatch] {
        pantryMatches.filter { !$0.isInStock }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    GlassStatRow {
                        GlassStatTile(title: "Ingredients", value: "\(recipe.ingredients.count)", symbol: "list.bullet", tint: .orange)
                        GlassStatTile(
                            title: "In stock",
                            value: "\(pantryMatches.count - missingIngredients.count)/\(pantryMatches.count)",
                            symbol: missingIngredients.isEmpty ? "checkmark.seal.fill" : "shippingbox.fill",
                            tint: missingIngredients.isEmpty ? .green : .blue
                        )
                    }
                    HStack {
                        Label("Servings", systemImage: "person.2.fill")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(servings)")
                            .font(.headline)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(servings)))
                        Stepper("Servings", value: $servings.animation(.snappy), in: 1...24)
                            .labelsHidden()
                    }
                    .glassCard(cornerRadius: 20)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if recipe.totalMinutes > 0 || !recipe.tagList.isEmpty || !recipe.sourceURL.isEmpty {
                Section {
                    if recipe.totalMinutes > 0 {
                        LabeledContent("Time") {
                            Text([recipe.prepMinutes > 0 ? "\(recipe.prepMinutes) min prep" : nil, recipe.cookMinutes > 0 ? "\(recipe.cookMinutes) min cook" : nil].compactMap { $0 }.joined(separator: " · "))
                        }
                    }
                    if !recipe.tagList.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(recipe.tagList, id: \.self) { tag in
                                    StatusBadge(text: tag, tint: .orange)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    if let url = URL(string: recipe.sourceURL), !recipe.sourceURL.isEmpty {
                        Link(destination: url) {
                            Label(url.host() ?? "Source", systemImage: "safari")
                        }
                    }
                }
            }

            if let facts = recipe.nutritionPerServing {
                Section {
                    NutritionRow(facts: facts)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    if servings != 1 {
                        Text("For \(servings) servings: \((facts * Double(servings)).summary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Nutrition per serving")
                } footer: {
                    Text(recipe.nutritionIsEstimated
                         ? "Estimated from the ingredients (\(Int((recipe.nutritionCoverage * 100).rounded()))% matched). Edit the recipe to enter exact values."
                         : "As declared by the recipe source.")
                }
            }

            if !recipe.instructions.isEmpty {
                Section("Instructions") {
                    ForEach(Array(InstructionSteps.split(recipe.instructions).enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.orange.gradient, in: .circle)
                            Text(step).font(.callout)
                        }
                    }
                }
            }

            Section {
                if pantryMatches.isEmpty {
                    Text("No ingredients added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pantryMatches) { match in
                        PantryMatchRow(match: match, isMissing: !match.isInStock)
                    }
                }
            } header: {
                Text("Ingredients")
            } footer: {
                if scale != 1 {
                    Text("Amounts scaled from \(recipe.servings) to \(servings) servings.")
                }
            }

            PrepCompanionsSection(recipe: recipe)

            if !missingIngredients.isEmpty {
                Section {
                    Button {
                        let count = MealPlanViewModel.addRequirementsToGroceries(
                            missingIngredients,
                            modelContext: modelContext
                        )
                        addedCount = count
                    } label: {
                        Label("Add \(missingIngredients.count) missing to Groceries", systemImage: "cart.badge.plus")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: .orange) }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit recipe", systemImage: "pencil") { showingEditRecipe = true }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Plan", systemImage: "calendar.badge.plus") {
                    planContext = AddMealContext(date: .now, mealType: .dinner, recipe: recipe)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .sheet(isPresented: $showingEditRecipe) {
            RecipeFormView(recipe: recipe)
        }
        // On-screen awareness: tells Siri which recipe is showing, so requests like
        // "plan this for Friday" or "what do I need for this?" resolve to it.
        .userActivity("com.example.GroceryMang.viewRecipe") { activity in
            activity.title = recipe.name
            activity.appEntityIdentifier = EntityIdentifier(for: RecipeEntity.self, identifier: recipe.name)
        }
        .sheet(item: $planContext) { context in
            AddMealView(date: context.date, mealType: context.mealType, recipe: context.recipe)
        }
        .sensoryFeedback(.success, trigger: addedCount)
        .alert("Added to Groceries", isPresented: Binding(
            get: { addedCount != nil },
            set: { if !$0 { addedCount = nil } }
        )) {
            Button("OK") { addedCount = nil }
        } message: {
            Text("Missing ingredients for \(servings) servings have been added to your grocery list.")
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
    @State private var servings: Int
    @State private var ingredients: [DraftRecipeIngredient]
    @State private var prepMinutes: Int
    @State private var cookMinutes: Int
    @State private var tags: String
    @State private var sourceURL: String
    @State private var calories: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var quickLine = ""

    init(recipe: Recipe? = nil) {
        self.recipe = recipe
        _name = State(initialValue: recipe?.name ?? "")
        _instructions = State(initialValue: recipe?.instructions ?? "")
        _servings = State(initialValue: recipe?.servings ?? 2)
        _ingredients = State(initialValue: recipe?.orderedIngredients.map {
            DraftRecipeIngredient(name: $0.name, quantity: $0.requiredQuantity, unit: $0.unit, note: $0.note)
        } ?? [])
        _prepMinutes = State(initialValue: recipe?.prepMinutes ?? 0)
        _cookMinutes = State(initialValue: recipe?.cookMinutes ?? 0)
        _tags = State(initialValue: recipe?.tags ?? "")
        _sourceURL = State(initialValue: recipe?.sourceURL ?? "")
        _calories = State(initialValue: recipe?.caloriesPerServing ?? 0)
        _protein = State(initialValue: recipe?.proteinPerServing ?? 0)
        _carbs = State(initialValue: recipe?.carbsPerServing ?? 0)
        _fat = State(initialValue: recipe?.fatPerServing ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Name", text: $name)
                    Stepper(value: $servings, in: 1...24) {
                        LabeledContent("Serves", value: "\(servings)")
                    }
                    TextField("Instructions (one step per line)", text: $instructions, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("Details") {
                    Stepper(value: $prepMinutes, in: 0...600, step: 5) {
                        LabeledContent("Prep", value: "\(prepMinutes) min")
                    }
                    Stepper(value: $cookMinutes, in: 0...600, step: 5) {
                        LabeledContent("Cook", value: "\(cookMinutes) min")
                    }
                    TextField("Tags (comma separated)", text: $tags)
                    TextField("Source URL", text: $sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    LabeledContent("Calories") { TextField("auto", value: $calories, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                    LabeledContent("Protein (g)") { TextField("auto", value: $protein, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                    LabeledContent("Carbs (g)") { TextField("auto", value: $carbs, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                    LabeledContent("Fat (g)") { TextField("auto", value: $fat, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                } header: {
                    Text("Nutrition per serving")
                } footer: {
                    Text("Leave at 0 to estimate from the ingredients.")
                }

                Section {
                    if ingredients.isEmpty {
                        Text("Add the ingredients this recipe requires.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($ingredients) { $ingredient in
                            HStack {
                                TextField("Ingredient", text: $ingredient.name)
                                TextField("Amount", value: $ingredient.quantity, format: .number)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 72)
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

                    HStack {
                        TextField("Quick add: 2 cups flour", text: $quickLine)
                            .onSubmit(addQuickLine)
                        Button("Add", action: addQuickLine)
                            .disabled(quickLine.trimmingCharacters(in: .whitespaces).isEmpty)
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
                        let viewModel = RecipeViewModel(modelContext: modelContext)
                        viewModel.saveRecipe(
                            existing: recipe,
                            name: name,
                            instructions: instructions,
                            servings: servings,
                            ingredients: ingredients
                        )
                        let saved = recipe ?? ((try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []).first { $0.name == name.trimmingCharacters(in: .whitespacesAndNewlines) }
                        if let saved {
                            let facts = NutritionFacts(calories: calories, protein: protein, carbs: carbs, fat: fat)
                            viewModel.update(
                                saved,
                                nutrition: facts.isEmpty ? nil : facts,
                                prepMinutes: prepMinutes,
                                cookMinutes: cookMinutes,
                                tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                                sourceURL: sourceURL.trimmingCharacters(in: .whitespaces)
                            )
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func addQuickLine() {
        let parsed = IngredientLineParser.parse(quickLine)
        guard !parsed.name.isEmpty else { return }
        ingredients.append(DraftRecipeIngredient(name: parsed.name, quantity: parsed.quantity, unit: parsed.unit, note: parsed.note))
        quickLine = ""
    }
}

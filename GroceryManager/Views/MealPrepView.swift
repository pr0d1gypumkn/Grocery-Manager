import SwiftData
import SwiftUI

/// Suggests sets of recipes that share ingredients and steps, so a varied week
/// can be prepped in one session.
struct MealPrepView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]

    /// When set, every suggestion includes this recipe.
    var anchor: Recipe?
    /// First day to plan suggestions onto.
    var startDate: Date = .now

    @State private var bundleSize = 3
    @State private var bundles: [MealPrepBundle<Recipe>] = []
    @State private var isLoading = true
    @State private var toast: String?

    private var effectiveSize: Int { min(bundleSize, max(recipes.count, 2)) }

    private var sizeOptions: [Int] {
        Array(2...max(2, min(5, recipes.count)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if recipes.count < 2 {
                        ContentUnavailableView(
                            "Not enough recipes",
                            systemImage: "book.closed",
                            description: Text("Add at least two recipes to get prep suggestions.")
                        )
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if bundles.isEmpty {
                        ContentUnavailableView(
                            "No overlapping recipes",
                            systemImage: "square.stack.3d.up.slash",
                            description: Text(effectiveSize > 2
                                ? "Try fewer recipes, or add recipes that share ingredients."
                                : "None of your recipes share ingredients or cooking steps yet.")
                        )
                    } else {
                        ForEach(bundles) { bundle in
                            PrepBundleCard(
                                bundle: bundle,
                                startDate: startDate,
                                onPlan: { plan(bundle, as: $0) },
                                onShop: { shop(bundle) }
                            )
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .animation(.smooth, value: bundles.map(\.id))
            }
            .background { AmbientBackground(tint: .green) }
            .navigationTitle(anchor.map { "Prep with \($0.name)" } ?? "Prep Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
            .task(id: "\(effectiveSize)-\(recipes.count)") {
                isLoading = true
                let planner = MealPrepPlanner(recipes: recipes)
                bundles = planner.bundles(size: effectiveSize, anchor: anchor.map { anchor in { $0 === anchor } })
                isLoading = false
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
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation { self.toast = nil }
                        }
                }
            }
            .sensoryFeedback(.success, trigger: toast) { _, new in new != nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recipes that share ingredients and cooking steps, picked to cover as many food groups as possible, so one prep session gives you a varied week.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if recipes.count > 2 {
                Picker("Recipes per plan", selection: $bundleSize) {
                    ForEach(sizeOptions, id: \.self) { size in
                        Text("\(size) recipes").tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.top, 4)
    }

    private func plan(_ bundle: MealPrepBundle<Recipe>, as mealType: MealType) {
        MealPlanViewModel(modelContext: modelContext)
            .addMeals(bundle.items, startingOn: startDate, mealType: mealType)
        withAnimation {
            toast = "Planned \(bundle.items.count) \(mealType.rawValue.lowercased())s"
        }
    }

    private func shop(_ bundle: MealPrepBundle<Recipe>) {
        let requirements = bundle.items.flatMap { recipe in
            recipe.ingredients.map {
                IngredientRequirement(name: $0.name, quantity: $0.requiredQuantity, unit: $0.unit)
            }
        }
        let matches = PantryMatcher().matches(requirements: requirements, inventory: inventory)
        let count = MealPlanViewModel.addRequirementsToGroceries(matches, modelContext: modelContext)
        withAnimation {
            toast = count == 0
                ? "You have everything for these"
                : "Added \(count) item\(count == 1 ? "" : "s") to Groceries"
        }
    }
}

// MARK: - Bundle card

private struct PrepBundleCard: View {
    let bundle: MealPrepBundle<Recipe>
    let startDate: Date
    let onPlan: (MealType) -> Void
    let onShop: () -> Void

    private var savedIngredients: Int {
        bundle.totalIngredientCount - bundle.uniqueIngredientCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(bundle.items) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: "fork.knife", tint: .orange, size: 32)
                            Text(recipe.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            FoodGroupBadges(groups: bundle.groups)

            if !bundle.sharedIngredients.isEmpty {
                Text("**\(bundle.uniqueIngredientCount) ingredients** instead of \(bundle.totalIngredientCount) · shares \(bundle.sharedIngredients.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !bundle.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Batch prep")
                        .font(.subheadline.weight(.semibold))
                    ForEach(bundle.tasks) { task in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.subheadline)
                                Text("For \(task.recipeNames.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: task.symbol)
                                .foregroundStyle(.green)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Menu {
                    Section("One per day from \(startDate.formatted(.dateTime.weekday(.wide)))") {
                        ForEach(MealType.allCases) { type in
                            Button("As \(type.rawValue.lowercased())", systemImage: type.symbol) { onPlan(type) }
                        }
                    }
                } label: {
                    Label("Plan these", systemImage: "calendar.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.indigo)

                Button(action: onShop) {
                    Label("Shop", systemImage: "cart.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Add missing ingredients to Groceries")
            }
        }
        .glassCard(cornerRadius: 24)
        .accessibilityElement(children: .contain)
        .accessibilityHint(savedIngredients > 0 ? "Shares \(savedIngredients) ingredients between recipes" : "")
    }
}

// MARK: - Recipe companions

/// "Prep alongside" section for a recipe's detail page.
struct PrepCompanionsSection: View {
    let recipe: Recipe
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var companions: [PrepCompanion<Recipe>] = []
    @State private var showingPrepIdeas = false

    var body: some View {
        Group {
            if !companions.isEmpty {
                Section {
                    ForEach(companions) { companion in
                        NavigationLink {
                            RecipeDetailView(recipe: companion.item)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(companion.item.name)
                                    .font(.body.weight(.medium))
                                Text(summary(companion))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if !companion.addedGroups.isEmpty {
                                    FoodGroupBadges(groups: companion.addedGroups)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Button("Build a prep plan", systemImage: "square.stack.3d.up.fill") {
                        showingPrepIdeas = true
                    }
                } header: {
                    Text("Prep alongside")
                } footer: {
                    Text("These share ingredients or steps with \(recipe.name). Badges show food groups they add.")
                }
            }
        }
        .task(id: recipes.count) {
            companions = MealPrepPlanner(recipes: recipes).companions(for: { $0 === recipe })
        }
        .sheet(isPresented: $showingPrepIdeas) {
            MealPrepView(anchor: recipe)
        }
    }

    private func summary(_ companion: PrepCompanion<Recipe>) -> String {
        var parts: [String] = []
        if !companion.sharedIngredients.isEmpty {
            parts.append("Shares \(companion.sharedIngredients.joined(separator: ", "))")
        }
        if !companion.sharedTechniques.isEmpty {
            let names = PrepTechnique.allCases
                .filter(companion.sharedTechniques.contains)
                .map(\.displayName)
            parts.append("both use the \(names.joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }
}

private extension PrepTechnique {
    var displayName: String {
        switch self {
        case .oven: "oven"
        case .boil: "boiling pot"
        case .grill: "grill"
        case .steam: "steamer"
        case .blend: "blender"
        case .marinate: "marinade step"
        case .slowCook: "slow cooker"
        }
    }
}

#Preview {
    MealPrepView()
        .modelContainer(for: [MealPlanEntry.self, Recipe.self, Ingredient.self, GroceryItem.self], inMemory: true)
}

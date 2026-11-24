import SwiftData
import SwiftUI

/// Proposes a full week from the user's recipes; each meal can be swapped before applying.
struct AutoPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @Query private var households: [Household]

    let weekStart: Date
    let existing: [MealPlanEntry]

    @State private var proposals: [AutoPlanner.Proposal] = []
    @State private var excluded: [String: Set<String>] = [:]
    @State private var prices: PricedList?
    @State private var isLoading = true
    @State private var includeLunches = true
    @State private var settings = AppSettings.shared

    private var calendar: Calendar { .current }

    private var totalCents: Int { proposals.reduce(0) { $0 + $1.estimatedCents } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Weekday lunches too", isOn: $includeLunches)
                    if let prices, settings.weeklyBudgetCents > 0 {
                        LabeledContent("Estimated to buy") {
                            Text(settings.formatPrice(cents: totalCents, currency: prices.currency))
                                .foregroundStyle(totalCents > settings.weeklyBudgetCents ? .orange : .primary)
                        }
                        LabeledContent("Weekly budget", value: settings.formatPrice(cents: settings.weeklyBudgetCents))
                    }
                } footer: {
                    Text("Built from your recipes, what's in the pantry, your household's portions and diet tags. Meals already on the plan are kept.")
                }

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if proposals.isEmpty {
                    ContentUnavailableView("Nothing to plan", systemImage: "calendar.badge.checkmark", description: Text(recipes.count < 3 ? "Save a few more recipes first." : "Every slot this week is already planned."))
                } else {
                    ForEach(proposals) { proposal in
                        proposalRow(proposal)
                    }
                }
            }
            .navigationTitle("Plan my week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(proposals.count) meals", systemImage: "checkmark", role: .confirm) { apply() }
                        .disabled(proposals.isEmpty)
                }
            }
            .task(id: includeLunches) { await build() }
        }
    }

    private func proposalRow(_ proposal: AutoPlanner.Proposal) -> some View {
        let day = calendar.date(byAdding: .day, value: proposal.dayOffset, to: weekStart) ?? weekStart
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                IconTile(symbol: proposal.mealType.symbol, tint: proposal.mealType.tint, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(day.formatted(.dateTime.weekday(.wide))) \(proposal.mealType.rawValue.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(proposal.recipe.name).font(.body.weight(.semibold))
                }
                Spacer()
                Button("Swap", systemImage: "arrow.triangle.2.circlepath") { swap(proposal) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
            }
            if !proposal.reasons.isEmpty {
                Text(proposal.reasons.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func baseOptions() -> AutoPlanner.Options {
        let locked = existing.compactMap { entry -> (dayOffset: Int, mealType: MealType, recipe: Recipe)? in
            guard let recipe = entry.recipe else { return nil }
            let offset = calendar.dateComponents([.day], from: weekStart, to: entry.date).day ?? 0
            return (offset, entry.mealType, recipe)
        }
        let memberTags = households.first?.members.flatMap { member in
            member.dietTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } ?? []
        return AutoPlanner.Options(
            servingsPerMeal: households.first?.servingsPerMeal ?? 2,
            dietTags: settings.dietTags + memberTags,
            pantry: inventory,
            prices: prices,
            weeklyBudgetCents: settings.weeklyBudgetCents,
            excludeRecipeNames: [],
            locked: locked
        )
    }

    private func build() async {
        isLoading = true
        if prices == nil, EntitlementService.shared.hasFeature(.priceAwareShopping) {
            let unique = Dictionary(grouping: recipes.flatMap(\.ingredients), by: { IngredientNameMatcher.key($0.name) }).compactMap { $0.value.first }
            let lines = unique.map { PlannedGroceryLine(name: $0.name, quantity: $0.requiredQuantity, unit: $0.unit, category: "") }
            prices = await PriceService.price(lines, region: settings.region)
        }
        rebuild()
        isLoading = false
    }

    private func rebuild() {
        let slots = includeLunches ? AutoPlanner.defaultSlots : AutoPlanner.defaultSlots.filter { $0.mealType == .dinner }
        var results: [AutoPlanner.Proposal] = []
        let base = baseOptions()
        // Slot by slot, so a swap only changes that one slot. Each call is told what the
        // earlier slots spent and how many slots follow, so the weekly budget is shared.
        for (index, slot) in slots.enumerated() {
            var options = base
            options.excludeRecipeNames = excluded["\(slot.dayOffset)-\(slot.mealType.rawValue)"] ?? []
            options.locked = base.locked + results.map { ($0.dayOffset, $0.mealType, $0.recipe) }
            options.spentCents = results.reduce(0) { $0 + $1.estimatedCents }
            options.slotsAfter = slots.count - index - 1
            if let proposal = AutoPlanner().plan(recipes: recipes, slots: [slot], options: options).first {
                results.append(proposal)
            }
        }
        proposals = results
    }

    private func swap(_ proposal: AutoPlanner.Proposal) {
        excluded[proposal.id, default: []].insert(proposal.recipe.name)
        // Swapped past every recipe: start the cycle again rather than leave the slot empty.
        if excluded[proposal.id, default: []].count >= recipes.count {
            excluded[proposal.id] = [proposal.recipe.name]
        }
        withAnimation(.snappy) { rebuild() }
    }

    private func apply() {
        let viewModel = MealPlanViewModel(modelContext: modelContext)
        for proposal in proposals {
            guard let day = calendar.date(byAdding: .day, value: proposal.dayOffset, to: weekStart) else { continue }
            viewModel.addMeal(recipe: proposal.recipe, on: day, mealType: proposal.mealType, servings: proposal.servings, note: proposal.reasons.first ?? "")
        }
        dismiss()
    }
}

import Foundation

/// Fills a week from the user's own recipes using pantry contents, household size, diet
/// tags, time per slot and (in budget mode) estimated cost. Same scoring as the server's
/// planner, so a plan built offline matches one built online.
struct AutoPlanner {
    struct Slot: Hashable {
        var dayOffset: Int
        var mealType: MealType
        var maxMinutes: Int?
    }

    struct Candidate {
        var recipe: Recipe
        var ingredientKeys: [String]
    }

    struct Proposal: Identifiable, Equatable {
        var id: String { "\(dayOffset)-\(mealType.rawValue)" }
        var dayOffset: Int
        var mealType: MealType
        var recipe: Recipe
        var servings: Int
        var reasons: [String]
        var estimatedCents: Int

        static func == (lhs: Proposal, rhs: Proposal) -> Bool { lhs.id == rhs.id && lhs.recipe === rhs.recipe }
    }

    struct Options {
        var servingsPerMeal: Double
        var dietTags: [String]
        var pantry: [Ingredient]
        var prices: PricedList?
        var weeklyBudgetCents: Int
        var excludeRecipeNames: Set<String> = []
        var locked: [(dayOffset: Int, mealType: MealType, recipe: Recipe)] = []
    }

    static let defaultSlots: [Slot] = (0..<7).flatMap { day -> [Slot] in
        var slots = [Slot(dayOffset: day, mealType: .dinner)]
        if day < 5 { slots.append(Slot(dayOffset: day, mealType: .lunch, maxMinutes: 20)) }
        return slots
    }

    private static let mealTags: [MealType: [String]] = [
        .breakfast: ["breakfast", "brunch"],
        .lunch: ["lunch", "salad", "wrap", "soup", "leftovers", "quick"],
        .dinner: ["dinner", "main", "meal-prep"],
        .snack: ["snack", "no-cook"]
    ]

    func plan(recipes: [Recipe], slots: [Slot] = defaultSlots, options: Options) -> [Proposal] {
        let matcher = PantryMatcher()
        let candidates = recipes
            .filter { !$0.ingredients.isEmpty && !options.excludeRecipeNames.contains($0.name) && Self.fitsDiet($0, options.dietTags) }
            .map { Candidate(recipe: $0, ingredientKeys: $0.ingredients.map { IngredientNameMatcher.key($0.name) }) }
        var proposals: [Proposal] = []
        var usedKeys: Set<String> = []
        var usedRecipes: Set<String> = Set(options.locked.map(\.recipe.name))
        for lock in options.locked { lock.recipe.ingredients.forEach { usedKeys.insert(IngredientNameMatcher.key($0.name)) } }
        var spentCents = 0
        let servings = max(Int(options.servingsPerMeal.rounded(.up)), 1)

        for slot in slots {
            if options.locked.contains(where: { $0.dayOffset == slot.dayOffset && $0.mealType == slot.mealType }) { continue }
            var best: (candidate: Candidate, score: Double, reasons: [String], cost: Int)?
            for candidate in candidates where !usedRecipes.contains(candidate.recipe.name) {
                var score = 0.0
                var reasons: [String] = []
                let tags = candidate.recipe.tagList.map { $0.lowercased() }
                if (Self.mealTags[slot.mealType] ?? []).contains(where: tags.contains) {
                    score += 3
                    reasons.append("tagged for \(slot.mealType.rawValue.lowercased())")
                } else if slot.mealType == .breakfast {
                    score -= 4
                }

                let scale = candidate.recipe.servings > 0 ? Double(servings) / Double(candidate.recipe.servings) : 1
                let needs = candidate.recipe.ingredients.map { IngredientRequirement(name: $0.name, quantity: $0.requiredQuantity * scale, unit: $0.unit) }
                let matches = matcher.matches(requirements: needs, inventory: options.pantry)
                let coverage = matches.isEmpty ? 0 : Double(matches.filter(\.isInStock).count) / Double(matches.count)
                score += coverage * 4
                if coverage >= 0.6 { reasons.append("\(Int((coverage * 100).rounded()))% already in your pantry") }

                let overlap = candidate.ingredientKeys.filter { usedKeys.contains($0) && !PrepStaples.isStaple($0) }.count
                score += Double(min(overlap, 4)) * 0.75
                if overlap >= 2 { reasons.append("shares \(overlap) ingredients with the week") }

                if let max = slot.maxMinutes, candidate.recipe.totalMinutes > max { score -= 3 }
                else if slot.maxMinutes != nil, candidate.recipe.totalMinutes > 0 { reasons.append("\(candidate.recipe.totalMinutes) min fits your schedule") }

                var cost = 0
                if let prices = options.prices {
                    cost = matches.filter { !$0.isInStock }.reduce(0) { $0 + (prices.quote(for: $1.requiredName)?.priceCents ?? 0) }
                    if options.weeklyBudgetCents > 0 {
                        let remaining = options.weeklyBudgetCents - spentCents
                        let slotsLeft = max(slots.count - proposals.count, 1)
                        let perSlot = Double(remaining) / Double(slotsLeft)
                        if Double(cost) > perSlot * 1.5 { score -= 3 }
                        else if Double(cost) <= perSlot {
                            score += 1.5
                            let amount = (Decimal(cost) / 100).formatted(.currency(code: prices.currency).precision(.fractionLength(2)))
                            reasons.append("about \(amount) to buy")
                        }
                    }
                }
                if best == nil || score > best!.score { best = (candidate, score, reasons, cost) }
            }
            guard let best else { continue }
            proposals.append(Proposal(dayOffset: slot.dayOffset, mealType: slot.mealType, recipe: best.candidate.recipe, servings: servings, reasons: best.reasons, estimatedCents: best.cost))
            usedRecipes.insert(best.candidate.recipe.name)
            best.candidate.ingredientKeys.forEach { usedKeys.insert($0) }
            spentCents += best.cost
            if usedRecipes.count >= candidates.count { usedRecipes.removeAll() }
        }
        return proposals
    }

    static func fitsDiet(_ recipe: Recipe, _ dietTags: [String]) -> Bool {
        let tags = Set(recipe.tagList.map { $0.lowercased() })
        let keys = recipe.ingredients.map { IngredientNameMatcher.key($0.name) }
        func hasAny(_ words: [String]) -> Bool { keys.contains { key in words.contains { key.contains($0) } } }
        let meat = ["chicken", "beef", "pork", "lamb", "turkey", "bacon", "sausage", "ham", "steak"]
        let fish = ["fish", "salmon", "shrimp", "tuna", "cod", "prawn"]
        let dairy = ["milk", "cheese", "yogurt", "butter", "cream"]
        return dietTags.allSatisfy { diet in
            switch diet.lowercased() {
            case "vegetarian": return tags.contains("vegetarian") || tags.contains("vegan") || !hasAny(meat + fish)
            case "vegan": return tags.contains("vegan") || !hasAny(meat + fish + dairy + ["egg", "honey"])
            case "pescatarian": return !hasAny(meat)
            case "gluten-free": return !hasAny(["flour", "bread", "pasta", "tortilla", "noodle", "couscous", "barley", "pita"])
            case "dairy-free": return !hasAny(dairy)
            case "nut-free": return !hasAny(["almond", "walnut", "cashew", "peanut", "pecan", "pistachio", "hazelnut"])
            default: return true
            }
        }
    }
}

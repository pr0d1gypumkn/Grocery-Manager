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
        /// Already spent this week by meals planned in earlier calls (for the budget).
        var spentCents: Int = 0
        /// Slots still to be planned after this call, so the budget is shared across them.
        var slotsAfter: Int = 0
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

    /// Fills every slot that isn't locked. Recipes aren't repeated until every candidate has
    /// been used once (same rule as the server's planner); after that the best repeat wins,
    /// kept away from the days it is already on.
    func plan(recipes: [Recipe], slots: [Slot] = defaultSlots, options: Options) -> [Proposal] {
        var state = State(options: options)
        let candidates = Self.candidates(from: recipes, options: options)
        var proposals: [Proposal] = []

        for (index, slot) in slots.enumerated() {
            if options.locked.contains(where: { $0.dayOffset == slot.dayOffset && $0.mealType == slot.mealType }) { continue }
            let slotsLeft = slots.count - index + options.slotsAfter
            guard let best = ranked(candidates, for: slot, state: state, options: options, slotsLeft: slotsLeft).first else { continue }
            proposals.append(Proposal(dayOffset: slot.dayOffset, mealType: slot.mealType, recipe: best.recipe, servings: state.servings, reasons: best.reasons, estimatedCents: best.cost))
            state.record(best.recipe, on: slot.dayOffset, cost: best.cost)
        }
        return proposals
    }

    /// Other recipes for one slot, best first, for swapping a meal that is already planned.
    func alternatives(for slot: Slot, recipes: [Recipe], options: Options, limit: Int = 5) -> [Proposal] {
        let state = State(options: options)
        let results = ranked(Self.candidates(from: recipes, options: options), for: slot, state: state, options: options, slotsLeft: 1 + options.slotsAfter, allowRepeats: true)
        return results.prefix(limit).map {
            Proposal(dayOffset: slot.dayOffset, mealType: slot.mealType, recipe: $0.recipe, servings: state.servings, reasons: $0.reasons, estimatedCents: $0.cost)
        }
    }

    // MARK: - Scoring

    private struct Scored {
        var recipe: Recipe
        var score: Double
        var reasons: [String]
        var cost: Int
    }

    /// What has been planned so far: which recipes on which days, shared ingredients, spend.
    private struct State {
        var usedKeys: Set<String> = []
        var days: [String: [Int]] = [:]
        var spentCents: Int
        var servings: Int

        init(options: Options) {
            spentCents = options.spentCents
            servings = max(Int(options.servingsPerMeal.rounded(.up)), 1)
            for lock in options.locked {
                days[lock.recipe.name, default: []].append(lock.dayOffset)
                lock.recipe.ingredients.forEach { usedKeys.insert(IngredientNameMatcher.key($0.name)) }
            }
        }

        mutating func record(_ recipe: Recipe, on day: Int, cost: Int) {
            days[recipe.name, default: []].append(day)
            recipe.ingredients.forEach { usedKeys.insert(IngredientNameMatcher.key($0.name)) }
            spentCents += cost
        }
    }

    private static func candidates(from recipes: [Recipe], options: Options) -> [Candidate] {
        recipes
            .filter { !$0.ingredients.isEmpty && !options.excludeRecipeNames.contains($0.name) && fitsDiet($0, options.dietTags) }
            .map { Candidate(recipe: $0, ingredientKeys: $0.ingredients.map { IngredientNameMatcher.key($0.name) }) }
    }

    private func ranked(_ candidates: [Candidate], for slot: Slot, state: State, options: Options, slotsLeft: Int, allowRepeats: Bool = false) -> [Scored] {
        let fresh = candidates.filter { state.days[$0.recipe.name] == nil }
        // Out of new recipes: repeat rather than leave the slot empty.
        let pool = allowRepeats || fresh.isEmpty ? candidates : fresh
        return pool
            .map { score($0, for: slot, state: state, options: options, slotsLeft: slotsLeft) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.recipe.name < $1.recipe.name }
    }

    private func score(_ candidate: Candidate, for slot: Slot, state: State, options: Options, slotsLeft: Int) -> Scored {
        var score = 0.0
        var reasons: [String] = []
        let tags = candidate.recipe.tagList.map { $0.lowercased() }
        if (Self.mealTags[slot.mealType] ?? []).contains(where: tags.contains) {
            score += 3
            reasons.append("tagged for \(slot.mealType.rawValue.lowercased())")
        } else if slot.mealType == .breakfast {
            score -= 4
        }

        let scale = candidate.recipe.servings > 0 ? Double(state.servings) / Double(candidate.recipe.servings) : 1
        let needs = candidate.recipe.ingredients.map { IngredientRequirement(name: $0.name, quantity: $0.requiredQuantity * scale, unit: $0.unit) }
        let matches = PantryMatcher().matches(requirements: needs, inventory: options.pantry)
        let coverage = matches.isEmpty ? 0 : Double(matches.filter(\.isInStock).count) / Double(matches.count)
        score += coverage * 4
        if coverage >= 0.6 { reasons.append("\(Int((coverage * 100).rounded()))% already in your pantry") }

        let overlap = candidate.ingredientKeys.filter { state.usedKeys.contains($0) && !PrepStaples.isStaple($0) }.count
        score += Double(min(overlap, 4)) * 0.75
        if overlap >= 2 { reasons.append("shares \(overlap) ingredients with the week") }

        if let max = slot.maxMinutes, candidate.recipe.totalMinutes > max { score -= 3 }
        else if slot.maxMinutes != nil, candidate.recipe.totalMinutes > 0 { reasons.append("\(candidate.recipe.totalMinutes) min fits your schedule") }

        if let days = state.days[candidate.recipe.name] {
            score -= 2 * Double(days.count)
            if days.contains(where: { abs($0 - slot.dayOffset) <= 1 }) { score -= 3 }
            reasons.append(days.count == 1 ? "already planned this week" : "already planned \(days.count)× this week")
        }

        var cost = 0
        if let prices = options.prices {
            cost = matches.filter { !$0.isInStock }.reduce(0) { $0 + (prices.quote(for: $1.requiredName)?.priceCents ?? 0) }
            if options.weeklyBudgetCents > 0 {
                let perSlot = Double(options.weeklyBudgetCents - state.spentCents) / Double(max(slotsLeft, 1))
                if Double(cost) > perSlot * 1.5 { score -= 3 }
                else if Double(cost) <= perSlot {
                    score += 1.5
                    let amount = (Decimal(cost) / 100).formatted(.currency(code: prices.currency).precision(.fractionLength(2)))
                    reasons.append("about \(amount) to buy")
                }
            }
        }
        return Scored(recipe: candidate.recipe, score: score, reasons: reasons, cost: cost)
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

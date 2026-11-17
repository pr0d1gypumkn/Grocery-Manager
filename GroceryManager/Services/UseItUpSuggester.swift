import Foundation

/// A saved recipe that would use up stock that is about to expire.
struct UseItUpSuggestion: Identifiable {
    let recipe: Recipe
    let expiringIngredients: [String]
    let missingCount: Int
    let score: Double

    var id: ObjectIdentifier { ObjectIdentifier(recipe) }
}

/// Picks recipes from the user's own collection that use what is expiring soonest and
/// can mostly be made from stock. Nothing external: it only ranks what the user saved.
enum UseItUpSuggester {
    static func expiringItems(in inventory: [Ingredient], now: Date = .now, horizonDays: Int = 4) -> [Ingredient] {
        let cutoff = Calendar.current.date(byAdding: .day, value: horizonDays, to: now) ?? now
        return inventory
            .filter { $0.quantity > 0 && $0.expiryDate >= now && $0.expiryDate <= cutoff && !$0.isPreparedMeal }
            .sorted { $0.expiryDate < $1.expiryDate }
    }

    static func suggestions(
        recipes: [Recipe],
        inventory: [Ingredient],
        now: Date = .now,
        horizonDays: Int = 4,
        limit: Int = 5
    ) -> [UseItUpSuggestion] {
        let expiring = expiringItems(in: inventory, now: now, horizonDays: horizonDays)
        guard !expiring.isEmpty else { return [] }
        let matcher = PantryMatcher()

        return recipes
            .filter { !$0.ingredients.isEmpty }
            .compactMap { recipe -> UseItUpSuggestion? in
                var urgency = 0.0
                var used: [String] = []
                for item in expiring where recipe.ingredients.contains(where: { IngredientNameMatcher.matches($0.name, item.name) }) {
                    let days = max(Calendar.current.dateComponents([.day], from: now, to: item.expiryDate).day ?? 0, 0)
                    urgency += 1 / Double(days + 1)
                    if !used.contains(item.name) { used.append(item.name) }
                }
                guard !used.isEmpty else { return nil }
                let matches = matcher.matches(recipeIngredients: recipe.ingredients, inventory: inventory, now: now)
                let missing = matches.filter { !$0.isInStock }.count
                let readiness = matches.isEmpty ? 0 : Double(matches.count - missing) / Double(matches.count)
                return UseItUpSuggestion(
                    recipe: recipe,
                    expiringIngredients: used,
                    missingCount: missing,
                    score: urgency * 2 + readiness
                )
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}

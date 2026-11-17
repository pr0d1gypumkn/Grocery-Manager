import Foundation

/// A recipe the user hasn't saved, with why it was picked.
struct RecipeSuggestion: Identifiable, Equatable {
    var id: String
    var name: String
    var servings: Int
    var tags: [String]
    var prepMinutes: Int
    var cookMinutes: Int
    var ingredients: [DraftRecipeIngredient]
    var instructions: [String]
    var reasons: [String]

    var draft: ImportedRecipeDraft {
        var parsed = ParsedRecipe(name: name, ingredientLines: [], instructions: instructions, servings: servings)
        parsed.tags = tags
        parsed.prepMinutes = prepMinutes
        parsed.cookMinutes = cookMinutes
        var draft = ImportedRecipeDraft(parsed: parsed, method: "suggestion")
        draft.ingredients = ingredients
        return draft
    }
}

protocol RecipeSuggestionSource: Sendable {
    func suggestions(savedNames: [String], savedTags: [String], pantry: [Ingredient], dietTags: [String], limit: Int) async throws -> [RecipeSuggestion]
}

/// The server's catalog (licensed feeds plug in there). Falls back to the built-in set.
struct ServerSuggestionSource: RecipeSuggestionSource {
    private struct Request: Encodable {
        struct Pantry: Encodable { var name: String; var quantity: Double; var unit: String; var expiryDate: Date }
        var savedNames: [String]; var savedTags: [String]; var pantry: [Pantry]; var dietTags: [String]; var limit: Int
    }
    private struct Response: Decodable {
        struct Item: Decodable {
            struct Recipe: Decodable {
                struct Ingredient: Decodable { var name: String; var quantity: Double; var unit: String }
                var id: String; var name: String; var servings: Int; var tags: [String]; var prepMinutes: Int; var cookMinutes: Int
                var ingredients: [Ingredient]; var instructions: [String]
            }
            var recipe: Recipe; var reasons: [String]
        }
        var suggestions: [Item]
    }

    func suggestions(savedNames: [String], savedTags: [String], pantry: [Ingredient], dietTags: [String], limit: Int) async throws -> [RecipeSuggestion] {
        let request = Request(savedNames: savedNames, savedTags: savedTags, pantry: pantry.map { .init(name: $0.name, quantity: $0.quantity, unit: $0.unit, expiryDate: $0.expiryDate) }, dietTags: dietTags, limit: limit)
        let response = try await APIClient.shared.post("/api/suggestions", body: request, as: Response.self)
        return response.suggestions.map { item in
            RecipeSuggestion(id: item.recipe.id, name: item.recipe.name, servings: item.recipe.servings, tags: item.recipe.tags, prepMinutes: item.recipe.prepMinutes, cookMinutes: item.recipe.cookMinutes,
                             ingredients: item.recipe.ingredients.map { DraftRecipeIngredient(name: $0.name, quantity: $0.quantity, unit: $0.unit) }, instructions: item.recipe.instructions, reasons: item.reasons)
        }
    }
}

/// Built-in ideas so the feature works offline. Mirrors web/src/lib/catalog.json.
struct BuiltInSuggestionSource: RecipeSuggestionSource {
    struct Entry { var id: String; var name: String; var servings: Int; var tags: [String]; var prep: Int; var cook: Int; var ingredients: [(String, Double, String)]; var steps: [String] }

    static let catalog: [Entry] = [
        Entry(id: "cat-1", name: "Garlic Butter Shrimp Pasta", servings: 4, tags: ["dinner", "quick", "pescatarian"], prep: 10, cook: 15,
              ingredients: [("shrimp", 450, "g"), ("pasta", 350, "g"), ("butter", 3, "tbsp"), ("garlic", 4, "item"), ("lemon", 1, "item"), ("parsley", 1, "item")],
              steps: ["Boil the pasta for 10 minutes.", "Melt butter in a skillet, cook garlic for 1 minute, then the shrimp for 4 minutes.", "Toss with pasta, lemon juice and parsley."]),
        Entry(id: "cat-2", name: "Thai Peanut Noodle Bowls", servings: 4, tags: ["dinner", "vegetarian", "meal-prep"], prep: 15, cook: 10,
              ingredients: [("rice noodles", 250, "g"), ("peanut butter", 3, "tbsp"), ("soy sauce", 3, "tbsp"), ("lime", 2, "item"), ("carrots", 2, "item"), ("bell peppers", 1, "item"), ("green onions", 3, "item"), ("garlic", 2, "item")],
              steps: ["Soak the rice noodles for 8 minutes.", "Whisk peanut butter, soy sauce, lime juice and minced garlic.", "Julienne the carrots and peppers, toss everything together."]),
        Entry(id: "cat-3", name: "Turkey Taco Skillet", servings: 4, tags: ["dinner", "high-protein", "quick", "gluten-free"], prep: 10, cook: 20,
              ingredients: [("ground turkey", 500, "g"), ("black beans", 1, "item"), ("canned tomatoes", 1, "item"), ("onion", 1, "item"), ("bell peppers", 1, "item"), ("cumin", 2, "tsp"), ("cheddar cheese", 80, "g")],
              steps: ["Dice the onion and pepper.", "Brown the turkey for 6 minutes, add onion and pepper for 4 minutes.", "Add beans, tomatoes and cumin; simmer for 10 minutes. Top with cheese."]),
        Entry(id: "cat-4", name: "Mediterranean Chickpea Bowls", servings: 4, tags: ["lunch", "vegan", "meal-prep", "gluten-free"], prep: 15, cook: 15,
              ingredients: [("chickpeas", 2, "item"), ("quinoa", 200, "g"), ("cucumber", 1, "item"), ("tomatoes", 2, "item"), ("red onion", 0.5, "item"), ("lemon", 1, "item"), ("olive oil", 3, "tbsp"), ("parsley", 1, "item")],
              steps: ["Boil the quinoa for 15 minutes.", "Dice the cucumber, tomatoes and onion.", "Toss with chickpeas, lemon, oil and parsley; chill."]),
        Entry(id: "cat-5", name: "Honey Garlic Salmon", servings: 2, tags: ["dinner", "pescatarian", "quick", "dairy-free"], prep: 5, cook: 15,
              ingredients: [("salmon fillets", 2, "item"), ("honey", 2, "tbsp"), ("soy sauce", 2, "tbsp"), ("garlic", 3, "item"), ("broccoli", 1, "item"), ("brown rice", 150, "g")],
              steps: ["Boil the rice for 30 minutes.", "Mix honey, soy sauce and minced garlic.", "Sear the salmon for 4 minutes per side, glaze, and steam the broccoli for 5 minutes."]),
        Entry(id: "cat-6", name: "Banana Oat Pancakes", servings: 2, tags: ["breakfast", "vegetarian", "quick"], prep: 5, cook: 10,
              ingredients: [("bananas", 2, "item"), ("rolled oats", 100, "g"), ("eggs", 2, "item"), ("milk", 100, "ml"), ("cinnamon", 1, "tsp"), ("butter", 1, "tbsp")],
              steps: ["Blend bananas, oats, eggs, milk and cinnamon.", "Fry small pancakes in butter for 2 minutes per side."]),
        Entry(id: "cat-7", name: "Lentil Bolognese", servings: 6, tags: ["dinner", "vegan", "freezer-friendly", "meal-prep"], prep: 10, cook: 35,
              ingredients: [("lentils", 300, "g"), ("canned tomatoes", 2, "item"), ("onion", 1, "item"), ("carrots", 2, "item"), ("garlic", 3, "item"), ("olive oil", 2, "tbsp"), ("pasta", 500, "g"), ("oregano", 1, "tsp")],
              steps: ["Dice the onion and carrots, mince the garlic.", "Cook the vegetables in oil for 8 minutes.", "Add lentils, tomatoes and oregano; simmer for 25 minutes.", "Boil the pasta for 10 minutes and serve."]),
        Entry(id: "cat-8", name: "Egg Fried Quinoa", servings: 3, tags: ["lunch", "vegetarian", "quick", "gluten-free", "leftovers"], prep: 5, cook: 12,
              ingredients: [("quinoa", 200, "g"), ("eggs", 3, "item"), ("frozen peas", 150, "g"), ("green onions", 3, "item"), ("soy sauce", 2, "tbsp"), ("ginger", 15, "g")],
              steps: ["Boil the quinoa for 15 minutes (or use leftovers).", "Scramble the eggs in a wok.", "Stir-fry peas, ginger and quinoa for 5 minutes, add soy sauce and green onions."]),
        Entry(id: "cat-9", name: "Greek Yogurt Chicken Salad", servings: 4, tags: ["lunch", "high-protein", "quick", "gluten-free"], prep: 15, cook: 0,
              ingredients: [("cooked chicken breast", 400, "g"), ("greek yogurt", 150, "g"), ("celery", 2, "item"), ("apple", 1, "item"), ("lemon", 1, "item"), ("walnuts", 40, "g")],
              steps: ["Dice the chicken, celery and apple.", "Mix with yogurt, lemon juice and walnuts; chill for 20 minutes."]),
        Entry(id: "cat-10", name: "Sweet Potato Black Bean Chili", servings: 6, tags: ["dinner", "vegan", "freezer-friendly", "gluten-free"], prep: 15, cook: 35,
              ingredients: [("sweet potatoes", 2, "item"), ("black beans", 2, "item"), ("canned tomatoes", 1, "item"), ("onion", 1, "item"), ("garlic", 3, "item"), ("chili powder", 2, "tbsp"), ("vegetable broth", 500, "ml"), ("corn", 150, "g")],
              steps: ["Dice the sweet potatoes and onion, mince the garlic.", "Cook onion and garlic for 5 minutes, add chili powder.", "Add sweet potato, beans, tomatoes, corn and broth; simmer for 30 minutes."])
    ]

    func suggestions(savedNames: [String], savedTags: [String], pantry: [Ingredient], dietTags: [String], limit: Int) async throws -> [RecipeSuggestion] {
        rank(savedNames: savedNames, savedTags: savedTags, pantry: pantry, dietTags: dietTags, limit: limit)
    }

    func rank(savedNames: [String], savedTags: [String], pantry: [Ingredient], dietTags: [String], limit: Int = 6) -> [RecipeSuggestion] {
        let saved = Set(savedNames.map { $0.lowercased() })
        var taste: [String: Int] = [:]
        for tag in savedTags.map({ $0.lowercased() }) { taste[tag, default: 0] += 1 }
        let pantryKeys = Set(pantry.filter { $0.quantity > 0 }.map { IngredientNameMatcher.key($0.name) })
        let diets = dietTags.map { $0.lowercased() }.filter { ["vegetarian", "vegan", "gluten-free", "dairy-free", "nut-free", "pescatarian"].contains($0) }

        return Self.catalog
            .filter { !saved.contains($0.name.lowercased()) }
            .filter { entry in diets.allSatisfy { entry.tags.contains($0) } }
            .map { entry -> (Double, RecipeSuggestion) in
                var reasons: [String] = []
                var score = 0.0
                let inPantry = entry.ingredients.filter { pantryKeys.contains(IngredientNameMatcher.key($0.0)) }.count
                if inPantry > 0 { score += Double(inPantry) * 1.5; reasons.append("\(inPantry) of \(entry.ingredients.count) ingredients in your pantry") }
                let hits = entry.tags.filter { taste[$0] != nil }
                if !hits.isEmpty { score += Double(hits.count) * 2; reasons.append("you like \(hits.prefix(2).joined(separator: " and ")) recipes") }
                if entry.prep + entry.cook <= 30 { score += 0.5; reasons.append("under 30 minutes") }
                return (score, RecipeSuggestion(id: entry.id, name: entry.name, servings: entry.servings, tags: entry.tags, prepMinutes: entry.prep, cookMinutes: entry.cook,
                                                ingredients: entry.ingredients.map { DraftRecipeIngredient(name: $0.0, quantity: $0.1, unit: $0.2) }, instructions: entry.steps, reasons: reasons))
            }
            .sorted { $0.0 > $1.0 }
            .prefix(limit)
            .map { $0.1 }
    }
}

@MainActor
enum SuggestionService {
    static func suggestions(savedRecipes: [Recipe], pantry: [Ingredient], dietTags: [String], limit: Int = 6) async -> [RecipeSuggestion] {
        let names = savedRecipes.map(\.name)
        let tags = savedRecipes.flatMap(\.tagList)
        if AccountSession.shared.isSignedIn, let remote = try? await ServerSuggestionSource().suggestions(savedNames: names, savedTags: tags, pantry: pantry, dietTags: dietTags, limit: limit), !remote.isEmpty {
            return remote
        }
        return BuiltInSuggestionSource().rank(savedNames: names, savedTags: tags, pantry: pantry, dietTags: dietTags, limit: limit)
    }
}

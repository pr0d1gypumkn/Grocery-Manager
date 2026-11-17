import Foundation
import SwiftData

/// Demo content that exercises the whole loop: recipes with overlapping ingredients, a
/// stocked kitchen with a few items about to expire, a planned week and a household.
@MainActor
enum DemoData {
    static func isEmpty(_ context: ModelContext) -> Bool {
        let recipes = (try? context.fetchCount(FetchDescriptor<Recipe>())) ?? 0
        let stock = (try? context.fetchCount(FetchDescriptor<Ingredient>())) ?? 0
        return recipes == 0 && stock == 0
    }

    /// Removes every record. Used by "Reset demo data" and tests.
    static func wipe(_ context: ModelContext) {
        try? context.delete(model: MealPlanEntry.self)
        try? context.delete(model: PrepBatch.self)
        try? context.delete(model: PrepSession.self)
        try? context.delete(model: GroceryItem.self)
        try? context.delete(model: RecipeIngredient.self)
        try? context.delete(model: Recipe.self)
        try? context.delete(model: Ingredient.self)
        try? context.delete(model: StorageLocation.self)
        try? context.delete(model: HouseholdMember.self)
        try? context.delete(model: Household.self)
        try? context.save()
    }

    @discardableResult
    static func load(into context: ModelContext, now: Date = .now) -> Int {
        let calendar = Calendar.current
        func days(_ count: Int) -> Date { calendar.date(byAdding: .day, value: count, to: now) ?? now }

        // Household
        let household = Household(name: "Home")
        context.insert(household)
        for (index, member) in [("Alex", 1.0), ("Sam", 1.0), ("Riley", 0.5)].enumerated() {
            let model = HouseholdMember(name: member.0, portionMultiplier: member.1, sortOrder: index)
            model.household = household
            context.insert(model)
        }

        // Locations
        let pantry = StorageLocation(name: "Pantry", icon: "cabinet.fill")
        let fridge = StorageLocation(name: "Fridge", icon: "refrigerator.fill")
        let freezer = StorageLocation(name: "Freezer", icon: "snowflake")
        [pantry, fridge, freezer].forEach(context.insert)

        // Stock (a few items expire soon so "use it up" has something to say)
        let stock: [(String, Double, String, String, Int, StorageLocation)] = [
            ("Chicken thighs", 900, "g", "Meat", 2, fridge),
            ("Greek yogurt", 500, "g", "Dairy", 3, fridge),
            ("Spinach", 200, "g", "Produce", 2, fridge),
            ("Eggs", 10, "item", "Dairy", 12, fridge),
            ("Milk", 1.5, "L", "Dairy", 6, fridge),
            ("Cheddar cheese", 250, "g", "Dairy", 20, fridge),
            ("Lemons", 3, "item", "Produce", 10, fridge),
            ("Carrots", 6, "item", "Produce", 14, fridge),
            ("Bell peppers", 2, "item", "Produce", 5, fridge),
            ("Garlic", 8, "item", "Produce", 30, pantry),
            ("Onions", 4, "item", "Produce", 21, pantry),
            ("Brown rice", 1.5, "kg", "Pantry", 365, pantry),
            ("Quinoa", 500, "g", "Pantry", 365, pantry),
            ("Chickpeas", 2, "item", "Pantry", 400, pantry),
            ("Black beans", 1, "item", "Pantry", 400, pantry),
            ("Olive oil", 500, "ml", "Pantry", 300, pantry),
            ("Soy sauce", 250, "ml", "Pantry", 365, pantry),
            ("Rolled oats", 800, "g", "Pantry", 200, pantry),
            ("Canned tomatoes", 2, "item", "Pantry", 400, pantry),
            ("Pasta", 500, "g", "Pantry", 365, pantry),
            ("Frozen peas", 750, "g", "Frozen", 180, freezer),
            ("Salmon fillets", 2, "item", "Frozen", 60, freezer)
        ]
        for (name, quantity, unit, category, expiry, location) in stock {
            context.insert(Ingredient(name: name, quantity: quantity, unit: unit, category: category, expiryDate: days(expiry), location: location))
        }

        // Recipes
        struct SeedRecipe {
            var name: String; var servings: Int; var prep: Int; var cook: Int; var tags: String
            var ingredients: [(String, Double, String)]; var steps: [String]
        }
        let recipes: [SeedRecipe] = [
            SeedRecipe(name: "Lemon Garlic Chicken Bowls", servings: 4, prep: 15, cook: 30, tags: "dinner, high-protein, meal-prep",
                ingredients: [("Chicken thighs", 700, "g"), ("Brown rice", 300, "g"), ("Broccoli", 1, "item"), ("Garlic", 4, "item"), ("Lemons", 1, "item"), ("Olive oil", 2, "tbsp"), ("Salt", 1, "tsp")],
                steps: ["Preheat the oven to 425°F.", "Mince the garlic and zest the lemon.", "Toss chicken with garlic, lemon zest, oil and salt; roast for 25 minutes.", "Boil the brown rice for 30 minutes.", "Cut the broccoli into florets and roast for the last 12 minutes.", "Divide rice, chicken and broccoli between bowls and squeeze lemon over."]),
            SeedRecipe(name: "Chickpea Spinach Curry", servings: 4, prep: 10, cook: 25, tags: "vegetarian, dinner, freezer-friendly",
                ingredients: [("Chickpeas", 2, "item"), ("Spinach", 200, "g"), ("Onions", 1, "item"), ("Garlic", 3, "item"), ("Canned tomatoes", 1, "item"), ("Coconut milk", 400, "ml"), ("Curry powder", 2, "tbsp"), ("Brown rice", 300, "g")],
                steps: ["Dice the onion and mince the garlic.", "Heat oil in a pot and cook the onion for 5 minutes until soft.", "Add garlic and curry powder, then the tomatoes, chickpeas and coconut milk; simmer for 15 minutes.", "Stir in the spinach until wilted.", "Boil the rice for 30 minutes and serve the curry over it."]),
            SeedRecipe(name: "Veggie Fried Rice", servings: 4, prep: 10, cook: 15, tags: "quick, vegetarian, leftovers",
                ingredients: [("Brown rice", 300, "g"), ("Eggs", 3, "item"), ("Carrots", 2, "item"), ("Frozen peas", 150, "g"), ("Green onions", 3, "item"), ("Garlic", 2, "item"), ("Soy sauce", 3, "tbsp"), ("Olive oil", 1, "tbsp")],
                steps: ["Dice the carrots and slice the green onions.", "Scramble the eggs in a wok over high heat, then set aside.", "Stir-fry the carrots, peas and garlic for 4 minutes.", "Add the cooked rice and soy sauce; stir-fry for 5 minutes.", "Fold in the eggs and green onions and serve."]),
            SeedRecipe(name: "Sheet Pan Salmon & Veg", servings: 2, prep: 10, cook: 20, tags: "dinner, quick, pescatarian",
                ingredients: [("Salmon fillets", 2, "item"), ("Bell peppers", 2, "item"), ("Broccoli", 1, "item"), ("Lemons", 1, "item"), ("Olive oil", 2, "tbsp"), ("Garlic", 2, "item")],
                steps: ["Preheat the oven to 425°F.", "Slice the peppers and cut the broccoli into florets.", "Toss vegetables with oil and minced garlic and roast for 10 minutes.", "Add the salmon, top with lemon slices, and roast for 12 minutes more."]),
            SeedRecipe(name: "Black Bean Quinoa Salad", servings: 4, prep: 15, cook: 15, tags: "lunch, vegan, meal-prep",
                ingredients: [("Quinoa", 200, "g"), ("Black beans", 1, "item"), ("Bell peppers", 1, "item"), ("Corn", 150, "g"), ("Lime", 2, "item"), ("Cilantro", 1, "item"), ("Olive oil", 3, "tbsp"), ("Cumin", 1, "tsp")],
                steps: ["Rinse the quinoa and boil for 15 minutes; let cool.", "Dice the pepper and chop the cilantro.", "Rinse and drain the black beans.", "Whisk lime juice, oil and cumin; toss everything together.", "Chill for 30 minutes before serving."]),
            SeedRecipe(name: "Overnight Oats", servings: 2, prep: 5, cook: 0, tags: "breakfast, no-cook",
                ingredients: [("Rolled oats", 100, "g"), ("Milk", 250, "ml"), ("Greek yogurt", 100, "g"), ("Honey", 1, "tbsp"), ("Blueberries", 100, "g"), ("Chia seeds", 1, "tbsp")],
                steps: ["Mix oats, milk, yogurt, honey and chia seeds in two jars.", "Refrigerate overnight.", "Top with blueberries before eating."]),
            SeedRecipe(name: "Veggie Egg Muffins", servings: 6, prep: 10, cook: 22, tags: "breakfast, high-protein, meal-prep, freezer-friendly",
                ingredients: [("Eggs", 8, "item"), ("Spinach", 100, "g"), ("Bell peppers", 1, "item"), ("Cheddar cheese", 80, "g"), ("Green onions", 2, "item"), ("Salt", 0.5, "tsp")],
                steps: ["Preheat the oven to 375°F and grease a muffin tin.", "Dice the pepper, chop the spinach and slice the green onions.", "Whisk the eggs with salt, stir in the vegetables and cheese.", "Divide between the cups and bake for 22 minutes.", "Cool completely before storing; freeze extras."]),
            SeedRecipe(name: "Pasta with Tomato Sauce", servings: 4, prep: 5, cook: 25, tags: "dinner, vegetarian, kid-friendly",
                ingredients: [("Pasta", 400, "g"), ("Canned tomatoes", 1, "item"), ("Onions", 1, "item"), ("Garlic", 3, "item"), ("Olive oil", 2, "tbsp"), ("Parmesan", 50, "g"), ("Basil", 1, "item")],
                steps: ["Dice the onion and mince the garlic.", "Cook the onion in oil over medium heat for 6 minutes, add the garlic and tomatoes, and simmer for 15 minutes.", "Boil the pasta for 10 minutes and drain.", "Toss the pasta with the sauce and top with parmesan and torn basil."]),
            SeedRecipe(name: "Chicken Caesar Wraps", servings: 4, prep: 15, cook: 15, tags: "lunch, quick",
                ingredients: [("Chicken thighs", 500, "g"), ("Romaine lettuce", 1, "item"), ("Tortillas", 4, "item"), ("Parmesan", 40, "g"), ("Greek yogurt", 100, "g"), ("Lemons", 1, "item"), ("Garlic", 1, "item")],
                steps: ["Sear the chicken in a skillet for 12 minutes, then slice.", "Chop the romaine.", "Whisk yogurt, lemon juice, minced garlic and parmesan into a dressing.", "Toss lettuce and chicken with the dressing and roll up in tortillas."]),
            SeedRecipe(name: "Carrot Ginger Soup", servings: 4, prep: 10, cook: 30, tags: "dinner, vegan, freezer-friendly",
                ingredients: [("Carrots", 8, "item"), ("Onions", 1, "item"), ("Ginger", 30, "g"), ("Garlic", 2, "item"), ("Vegetable broth", 1, "L"), ("Coconut milk", 200, "ml"), ("Olive oil", 1, "tbsp")],
                steps: ["Chop the carrots, dice the onion and grate the ginger.", "Cook the onion in oil for 5 minutes, add garlic and ginger for 1 minute.", "Add carrots and broth; simmer for 25 minutes.", "Blend until smooth, stir in the coconut milk and season."])
        ]

        var models: [String: Recipe] = [:]
        for seed in recipes {
            let recipe = Recipe(name: seed.name, instructions: seed.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"), servings: seed.servings)
            recipe.prepMinutes = seed.prep
            recipe.cookMinutes = seed.cook
            recipe.tags = seed.tags
            context.insert(recipe)
            for (index, ingredient) in seed.ingredients.enumerated() {
                recipe.ingredients.append(RecipeIngredient(name: ingredient.0, requiredQuantity: ingredient.1, unit: ingredient.2, sortOrder: index, recipe: recipe))
            }
            models[seed.name] = recipe
        }

        // This week's plan
        let week = now.weekDays
        let plan: [(Int, MealType, String, Int)] = [
            (0, .breakfast, "Overnight Oats", 2),
            (0, .dinner, "Lemon Garlic Chicken Bowls", 3),
            (1, .lunch, "Black Bean Quinoa Salad", 2),
            (1, .dinner, "Chickpea Spinach Curry", 3),
            (2, .breakfast, "Veggie Egg Muffins", 3),
            (2, .dinner, "Veggie Fried Rice", 3),
            (3, .lunch, "Chicken Caesar Wraps", 2),
            (3, .dinner, "Pasta with Tomato Sauce", 3),
            (4, .dinner, "Sheet Pan Salmon & Veg", 2),
            (5, .dinner, "Carrot Ginger Soup", 3)
        ]
        for (offset, mealType, name, servings) in plan {
            guard offset < week.count, let recipe = models[name] else { continue }
            context.insert(MealPlanEntry(date: week[offset], mealType: mealType, recipe: recipe, servings: servings))
        }

        // A couple of manual grocery lines
        context.insert(GroceryItem(name: "Paper towels", quantity: 1, unit: "item", category: "Other"))
        context.insert(GroceryItem(name: "Sparkling water", quantity: 12, unit: "item", category: "Beverages"))

        try? context.save()
        return recipes.count
    }
}

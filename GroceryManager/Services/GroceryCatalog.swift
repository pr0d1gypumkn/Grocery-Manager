import Foundation

/// Puts ingredient names into store sections, so the grocery list can be walked aisle by
/// aisle. Categories are the same strings `CategoryStyle.all` uses for stock.
enum AisleClassifier {
    /// Store-walk order: produce at the entrance, frozen last so it stays cold.
    static let aisleOrder = ["Produce", "Bakery", "Meat", "Seafood", "Dairy", "Pantry", "Beverages", "Frozen", "Other"]

    static func aisleIndex(for category: String) -> Int {
        aisleOrder.firstIndex(of: category) ?? aisleOrder.count
    }

    static func category(for name: String) -> String {
        let rawTokens = name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        if rawTokens.contains(where: { frozenWords.contains($0) }) { return "Frozen" }
        let key = IngredientNameMatcher.key(name)
        let tokens = key.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return "Other" }

        for (category, phrases) in rules {
            if phrases.contains(where: { tokens.containsPhrase($0) }) { return category }
        }
        switch FoodGroup.classify(name) {
        case .vegetables, .fruit: return "Produce"
        case .protein: return proteinCategory(tokens)
        case .dairy: return "Dairy"
        case .grains, .legumes, .healthyFats: return "Pantry"
        case nil: return PrepStaples.isStaple(name) ? "Pantry" : "Other"
        }
    }

    private static func proteinCategory(_ tokens: [String]) -> String {
        if tokens.contains(where: { seafoodWords.contains($0) }) { return "Seafood" }
        if tokens.contains(where: { ["egg", "tofu", "tempeh"].contains($0) }) { return "Dairy" }
        return "Meat"
    }

    private static let frozenWords: Set<String> = ["frozen", "ice", "popsicle"]
    private static let seafoodWords: Set<String> = ["fish", "salmon", "tuna", "cod", "tilapia", "shrimp", "prawn", "scallop", "crab", "sardine", "trout", "anchovy", "lobster", "mussel", "clam", "halibut"]

    private static let rules: [(String, [[String]])] = {
        let raw: [(String, [String])] = [
            ("Produce", ["lettuce", "spinach", "kale", "herb", "lemon", "lime", "avocado", "garlic", "onion", "ginger", "potato", "tomato", "cilantro", "parsley", "basil", "bell pepper", "red pepper", "green pepper", "jalapeno", "chili pepper"]),
            ("Bakery", ["bread", "bagel", "bun", "tortilla", "pita", "naan", "croissant", "baguette", "roll", "wrap", "muffin"]),
            ("Beverages", ["juice", "soda", "coffee", "tea", "beer", "wine", "sparkling water", "kombucha", "oat milk", "almond milk", "soy milk", "coconut water"]),
            ("Pantry", ["coconut milk", "tomato paste", "tomato sauce", "canned tomato"]),
            ("Dairy", ["milk", "butter", "yogurt", "yoghurt", "cheese", "cream", "egg", "kefir", "sour cream", "cream cheese", "tofu"]),
            ("Meat", ["chicken", "beef", "pork", "turkey", "lamb", "sausage", "bacon", "ham", "steak", "mince", "ground beef", "ground turkey", "deli", "salami", "prosciutto"]),
            ("Pantry", ["rice", "pasta", "flour", "sugar", "oil", "vinegar", "sauce", "spice", "canned", "can", "bean", "lentil", "chickpea", "broth", "stock", "honey", "peanut butter", "oat", "cereal", "quinoa", "nut", "seed", "salt", "pepper", "cumin", "paprika", "oregano", "cinnamon", "soy sauce", "tomato paste", "coconut milk", "noodle", "cracker", "chip"])
        ]
        return raw.map { category, phrases in
            (category, phrases.map { IngredientNameMatcher.key($0).split(separator: " ").map(String.init) }.filter { !$0.isEmpty })
        }
    }()
}

/// Default expiry windows and storage locations for food bought from the grocery list.
enum ShelfLife {
    static func defaultDays(for category: String) -> Int {
        switch category {
        case "Produce": 7
        case "Dairy": 10
        case "Meat", "Seafood": 3
        case "Bakery": 5
        case "Frozen": 90
        case "Beverages": 30
        case "Pantry": 180
        default: 30
        }
    }

    /// Fridge for perishables, freezer for frozen, pantry for everything else.
    static func preferredLocationName(for category: String) -> String {
        switch category {
        case "Produce", "Dairy", "Meat", "Seafood", "Beverages": "Fridge"
        case "Frozen": "Freezer"
        default: "Pantry"
        }
    }

    static func preferredLocation(for category: String, in locations: [StorageLocation]) -> StorageLocation? {
        let wanted = preferredLocationName(for: category).lowercased()
        return locations.first { $0.name.lowercased().contains(wanted) }
            ?? locations.first { $0.name.lowercased().contains("pantry") || $0.name.lowercased().contains("cupboard") }
            ?? locations.first
    }

    static func defaultExpiry(for category: String, from date: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: defaultDays(for: category), to: date) ?? date
    }
}

extension Array where Element == String {
    func containsPhrase(_ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= count else { return false }
        return (0...(count - phrase.count)).contains { start in
            Array(self[start..<(start + phrase.count)]) == phrase
        }
    }
}

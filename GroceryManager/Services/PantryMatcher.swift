import Foundation
import NaturalLanguage

struct PantryMatch: Identifiable, Equatable {
    let id: String
    let requiredName: String
    let requiredQuantity: Double
    let availableQuantity: Double
    let unit: String

    var isInStock: Bool {
        availableQuantity >= requiredQuantity
    }

    var missingQuantity: Double {
        max(requiredQuantity - availableQuantity, 0)
    }
}

struct PantryMatcher {
    func matches(
        recipeIngredients: [RecipeIngredient],
        inventory: [Ingredient],
        now: Date = .now
    ) -> [PantryMatch] {
        return recipeIngredients
            .map { ingredient in
                let availableQuantity = inventory
                    .filter { $0.expiryDate >= now && IngredientNameMatcher.matches($0.name, ingredient.name) }
                    .reduce(0) { total, inventoryItem in
                        total + (UnitConverter.convert(
                            inventoryItem.quantity,
                            from: inventoryItem.unit,
                            to: ingredient.unit
                        ) ?? 0)
                    }

                return PantryMatch(
                    id: "\(IngredientNameMatcher.key(ingredient.name))-\(ingredient.id)",
                    requiredName: ingredient.name,
                    requiredQuantity: ingredient.requiredQuantity,
                    availableQuantity: availableQuantity,
                    unit: ingredient.unit
                )
            }
    }

}

private enum IngredientNameMatcher {
    private static let preparationWords: Set<String> = [
        "fresh", "frozen", "dried", "dry", "canned", "jarred", "raw", "cooked",
        "chopped", "diced", "sliced", "minced", "grated", "shredded", "crushed",
        "ground", "melted", "softened", "room", "temperature", "baby", "leaves",
        "leaf", "optional", "organic"
    ]

    private static let aliases: [String: String] = [
        "scallions": "green onion",
        "scallion": "green onion",
        "coriander": "cilantro",
        "aubergine": "eggplant",
        "courgette": "zucchini",
        "capsicum": "pepper"
    ]

    static func matches(_ left: String, _ right: String) -> Bool {
        key(left) == key(right)
    }

    static func key(_ name: String) -> String {
        let tokens = tokenize(name)
            .map { aliases[$0] ?? $0 }
            .filter { !preparationWords.contains($0) }

        return tokens.joined(separator: " ")
    }

    private static func tokenize(_ name: String) -> [String] {
        let normalized = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = normalized

        var tokens: [String] = []
        let fullRange = normalized.startIndex..<normalized.endIndex
        tagger.enumerateTags(in: fullRange, unit: .word, scheme: .lemma, options: [.omitWhitespace, .omitPunctuation]) { tag, tokenRange in
            let token = String(normalized[tokenRange]).lowercased()
            let lemma = tag?.rawValue.lowercased() ?? token
            tokens.append(stem(lemma))
            return true
        }
        return tokens
    }

    private static func stem(_ token: String) -> String {
        if token.hasSuffix("ies") && token.count > 4 {
            return String(token.dropLast(3)) + "y"
        }
        if token.hasSuffix("es") && token.count > 4 {
            return String(token.dropLast(2))
        }
        if token.hasSuffix("s") && token.count > 3 {
            return String(token.dropLast())
        }
        return token
    }
}

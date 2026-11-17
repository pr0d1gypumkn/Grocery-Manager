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

/// A plain-value ingredient requirement, so needs from several recipes can be scaled and merged.
struct IngredientRequirement: Hashable {
    var name: String
    var quantity: Double
    var unit: String
}

struct PantryMatcher {
    func matches(
        recipeIngredients: [RecipeIngredient],
        inventory: [Ingredient],
        now: Date = .now
    ) -> [PantryMatch] {
        return recipeIngredients
            .map { ingredient in
                PantryMatch(
                    id: "\(IngredientNameMatcher.key(ingredient.name))-\(ingredient.id)",
                    requiredName: ingredient.name,
                    requiredQuantity: ingredient.requiredQuantity,
                    availableQuantity: available(ingredient.name, unit: ingredient.unit, in: inventory, now: now),
                    unit: ingredient.unit
                )
            }
    }

    /// Merges requirements that refer to the same ingredient (converting units where possible)
    /// and checks each merged requirement against stock.
    func matches(
        requirements: [IngredientRequirement],
        inventory: [Ingredient],
        now: Date = .now
    ) -> [PantryMatch] {
        merge(requirements).map { requirement in
            PantryMatch(
                id: "\(IngredientNameMatcher.key(requirement.name))-\(requirement.unit)",
                requiredName: requirement.name,
                requiredQuantity: requirement.quantity,
                availableQuantity: available(requirement.name, unit: requirement.unit, in: inventory, now: now),
                unit: requirement.unit
            )
        }
    }

    func merge(_ requirements: [IngredientRequirement]) -> [IngredientRequirement] {
        var merged: [IngredientRequirement] = []
        var keys: [String] = []

        for requirement in requirements {
            let key = IngredientNameMatcher.key(requirement.name)
            if let index = keys.indices.first(where: {
                keys[$0] == key && UnitConverter.convert(1, from: requirement.unit, to: merged[$0].unit) != nil
            }) {
                let converted = UnitConverter.convert(requirement.quantity, from: requirement.unit, to: merged[index].unit) ?? 0
                merged[index].quantity += converted
            } else {
                merged.append(requirement)
                keys.append(key)
            }
        }
        return merged
    }

    private func available(_ name: String, unit: String, in inventory: [Ingredient], now: Date) -> Double {
        inventory
            .filter { $0.expiryDate >= now && IngredientNameMatcher.matches($0.name, name) }
            .reduce(0) { total, item in
                total + (UnitConverter.convert(item.quantity, from: item.unit, to: unit) ?? 0)
            }
    }
}

enum IngredientNameMatcher {
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

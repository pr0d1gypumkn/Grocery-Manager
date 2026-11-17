import Foundation

/// Calories and macros. Protein, carbs and fat are in grams.
struct NutritionFacts: Codable, Equatable, Hashable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static let zero = NutritionFacts()

    var isEmpty: Bool { calories == 0 && protein == 0 && carbs == 0 && fat == 0 }

    static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein, carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }

    static func * (lhs: NutritionFacts, factor: Double) -> NutritionFacts {
        NutritionFacts(calories: lhs.calories * factor, protein: lhs.protein * factor, carbs: lhs.carbs * factor, fat: lhs.fat * factor)
    }

    static func / (lhs: NutritionFacts, divisor: Double) -> NutritionFacts {
        guard divisor != 0 else { return lhs }
        return lhs * (1 / divisor)
    }

    var summary: String {
        "\(Int(calories.rounded())) kcal · P \(Int(protein.rounded()))g · C \(Int(carbs.rounded()))g · F \(Int(fat.rounded()))g"
    }
}

/// Reference values for one ingredient: per 100 g, plus how heavy one item or one cup is,
/// so count and volume measures can be turned into grams.
struct NutritionEntry: Equatable {
    var per100g: NutritionFacts
    var gramsPerItem: Double?
    var gramsPerCup: Double?
}

struct NutritionEstimate: Equatable {
    var facts: NutritionFacts
    var matchedCount: Int
    var totalCount: Int

    var coverage: Double { totalCount == 0 ? 0 : Double(matchedCount) / Double(totalCount) }
}

/// Estimates recipe nutrition from a bundled table of common ingredients. Imported recipes
/// that declare their own nutrition keep it; this is for everything the user types in.
enum NutritionEstimator {
    static func estimate(_ requirements: [IngredientRequirement]) -> NutritionEstimate {
        var total = NutritionFacts.zero
        var matched = 0
        for requirement in requirements where !PrepStaples.isStaple(requirement.name) || NutritionTable.entry(for: requirement.name) != nil {
            guard let entry = NutritionTable.entry(for: requirement.name),
                  let grams = grams(for: requirement.quantity, unit: requirement.unit, entry: entry) else { continue }
            total = total + entry.per100g * (grams / 100)
            matched += 1
        }
        let counted = requirements.filter { !PrepStaples.isStaple($0.name) || NutritionTable.entry(for: $0.name) != nil }.count
        return NutritionEstimate(facts: total, matchedCount: matched, totalCount: counted)
    }

    static func grams(for quantity: Double, unit: String, entry: NutritionEntry) -> Double? {
        guard let quantityUnit = QuantityUnit(rawValue: unit) else { return nil }
        switch quantityUnit {
        case .grams, .kilograms, .ounces, .pounds:
            return UnitConverter.convert(quantity, from: unit, to: QuantityUnit.grams.rawValue)
        case .item, .serving:
            return quantity * (entry.gramsPerItem ?? 100)
        case .dozen:
            return quantity * 12 * (entry.gramsPerItem ?? 100)
        default:
            guard let ml = UnitConverter.convert(quantity, from: unit, to: QuantityUnit.milliliters.rawValue) else { return nil }
            let density = (entry.gramsPerCup ?? 236.5882365) / 236.5882365
            return ml * density
        }
    }
}

extension Recipe {
    var declaredNutrition: NutritionFacts? {
        let facts = NutritionFacts(calories: caloriesPerServing, protein: proteinPerServing, carbs: carbsPerServing, fat: fatPerServing)
        return facts.isEmpty ? nil : facts
    }

    var requirementsPerBatch: [IngredientRequirement] {
        ingredients.map { IngredientRequirement(name: $0.name, quantity: $0.requiredQuantity, unit: $0.unit) }
    }

    /// Declared nutrition if the source provided it, otherwise an estimate from the ingredients.
    var nutritionPerServing: NutritionFacts? {
        if let declaredNutrition { return declaredNutrition }
        let estimate = NutritionEstimator.estimate(requirementsPerBatch)
        guard estimate.matchedCount > 0, servings > 0 else { return nil }
        return estimate.facts / Double(servings)
    }

    var nutritionIsEstimated: Bool { declaredNutrition == nil }

    var nutritionCoverage: Double {
        declaredNutrition == nil ? NutritionEstimator.estimate(requirementsPerBatch).coverage : 1
    }
}

extension MealPlanEntry {
    /// Nutrition for everything on the plate(s) in this entry.
    var nutrition: NutritionFacts? {
        guard let perServing = recipe?.nutritionPerServing else { return nil }
        return perServing * Double(servings)
    }
}

// MARK: - Reference table

enum NutritionTable {
    static func entry(for name: String) -> NutritionEntry? {
        let tokens = IngredientNameMatcher.key(name).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }
        return rules.first { tokens.containsPhrase($0.tokens) }?.entry
    }

    private static func e(_ calories: Double, _ protein: Double, _ carbs: Double, _ fat: Double, item: Double? = nil, cup: Double? = nil) -> NutritionEntry {
        NutritionEntry(per100g: NutritionFacts(calories: calories, protein: protein, carbs: carbs, fat: fat), gramsPerItem: item, gramsPerCup: cup)
    }

    /// Longest phrase first so "sweet potato" wins over "potato".
    private static let rules: [(tokens: [String], entry: NutritionEntry)] = {
        let raw: [(String, NutritionEntry)] = [
            // Proteins
            ("chicken breast", e(165, 31, 0, 3.6, item: 174, cup: 140)),
            ("chicken thigh", e(209, 26, 0, 10.9, item: 110, cup: 140)),
            ("chicken", e(190, 28, 0, 8, item: 150, cup: 140)),
            ("ground beef", e(254, 17, 0, 20, cup: 225)),
            ("beef", e(250, 26, 0, 15, item: 200, cup: 225)),
            ("steak", e(250, 26, 0, 15, item: 200)),
            ("pork", e(242, 27, 0, 14, item: 150)),
            ("ground turkey", e(149, 19, 0, 8, cup: 225)),
            ("turkey", e(149, 19, 0, 8, item: 150)),
            ("lamb", e(294, 25, 0, 21, item: 150)),
            ("bacon", e(541, 37, 1.4, 42, item: 8)),
            ("sausage", e(301, 12, 1, 27, item: 75)),
            ("ham", e(145, 21, 1.5, 6, item: 30)),
            ("salmon", e(208, 20, 0, 13, item: 170)),
            ("tuna", e(116, 26, 0, 1, item: 142)),
            ("shrimp", e(99, 24, 0.2, 0.3, item: 7, cup: 145)),
            ("prawn", e(99, 24, 0.2, 0.3, item: 7, cup: 145)),
            ("cod", e(82, 18, 0, 0.7, item: 150)),
            ("tilapia", e(96, 20, 0, 1.7, item: 150)),
            ("fish", e(100, 20, 0, 2, item: 150)),
            ("egg", e(143, 13, 0.7, 9.5, item: 50, cup: 243)),
            ("tofu", e(76, 8, 1.9, 4.8, item: 350, cup: 250)),
            ("tempeh", e(192, 20, 8, 11, item: 225, cup: 166)),
            // Dairy
            ("almond milk", e(17, 0.6, 0.6, 1.2, cup: 240)),
            ("oat milk", e(45, 1, 7, 1.5, cup: 240)),
            ("coconut milk", e(230, 2.3, 5.5, 24, item: 400, cup: 240)),
            ("milk", e(61, 3.2, 4.8, 3.3, cup: 244)),
            ("greek yogurt", e(59, 10, 3.6, 0.4, cup: 245)),
            ("yogurt", e(61, 3.5, 4.7, 3.3, cup: 245)),
            ("cream cheese", e(342, 6, 4, 34, cup: 232)),
            ("sour cream", e(198, 2.4, 4.6, 19, cup: 230)),
            ("heavy cream", e(340, 2.8, 2.8, 36, cup: 238)),
            ("whipping cream", e(340, 2.8, 2.8, 36, cup: 238)),
            ("cottage cheese", e(98, 11, 3.4, 4.3, cup: 226)),
            ("parmesan", e(431, 38, 4, 29, cup: 100)),
            ("mozzarella", e(280, 28, 3, 17, cup: 112)),
            ("feta", e(264, 14, 4, 21, cup: 150)),
            ("cheddar", e(403, 25, 1.3, 33, cup: 113)),
            ("cheese", e(380, 24, 2, 31, cup: 113)),
            ("butter", e(717, 0.9, 0.1, 81, item: 113, cup: 227)),
            ("cream", e(340, 2.8, 2.8, 36, cup: 238)),
            // Grains & bakery
            ("brown rice", e(370, 7.5, 77, 2.7, cup: 190)),
            ("rice", e(365, 7, 80, 0.7, cup: 185)),
            ("quinoa", e(368, 14, 64, 6, cup: 170)),
            ("couscous", e(376, 13, 77, 0.6, cup: 173)),
            ("spaghetti", e(371, 13, 75, 1.5, cup: 100)),
            ("penne", e(371, 13, 75, 1.5, cup: 100)),
            ("pasta", e(371, 13, 75, 1.5, cup: 100)),
            ("noodle", e(371, 13, 75, 1.5, cup: 100)),
            ("tortilla", e(312, 8, 52, 8, item: 45)),
            ("pita", e(275, 9, 55, 1.2, item: 60)),
            ("bread", e(265, 9, 49, 3.2, item: 30)),
            ("oat", e(389, 17, 66, 7, cup: 90)),
            ("flour", e(364, 10, 76, 1, cup: 125)),
            ("cereal", e(379, 8, 84, 3, cup: 30)),
            ("cracker", e(500, 7, 61, 25, item: 3)),
            // Produce
            ("sweet potato", e(86, 1.6, 20, 0.1, item: 130, cup: 133)),
            ("potato", e(77, 2, 17, 0.1, item: 213, cup: 150)),
            ("green onion", e(32, 1.8, 7.3, 0.2, item: 15, cup: 100)),
            ("red onion", e(40, 1.1, 9.3, 0.1, item: 110, cup: 160)),
            ("onion", e(40, 1.1, 9.3, 0.1, item: 110, cup: 160)),
            ("garlic", e(149, 6.4, 33, 0.5, item: 3, cup: 136)),
            ("ginger", e(80, 1.8, 18, 0.8, item: 30, cup: 96)),
            ("tomato paste", e(82, 4.3, 19, 0.5, cup: 262)),
            ("tomato sauce", e(29, 1.3, 5.3, 0.3, cup: 245)),
            ("tomato", e(18, 0.9, 3.9, 0.2, item: 123, cup: 180)),
            ("carrot", e(41, 0.9, 9.6, 0.2, item: 61, cup: 128)),
            ("celery", e(16, 0.7, 3, 0.2, item: 40, cup: 101)),
            ("bell pepper", e(31, 1, 6, 0.3, item: 120, cup: 150)),
            ("pepper", e(31, 1, 6, 0.3, item: 120, cup: 150)),
            ("broccoli", e(34, 2.8, 7, 0.4, item: 300, cup: 91)),
            ("cauliflower", e(25, 1.9, 5, 0.3, item: 580, cup: 107)),
            ("spinach", e(23, 2.9, 3.6, 0.4, cup: 30)),
            ("kale", e(49, 4.3, 9, 0.9, cup: 67)),
            ("lettuce", e(15, 1.4, 2.9, 0.2, item: 300, cup: 36)),
            ("cucumber", e(15, 0.7, 3.6, 0.1, item: 300, cup: 104)),
            ("zucchini", e(17, 1.2, 3.1, 0.3, item: 196, cup: 124)),
            ("mushroom", e(22, 3.1, 3.3, 0.3, item: 18, cup: 70)),
            ("lemon", e(29, 1.1, 9.3, 0.3, item: 58, cup: 244)),
            ("lime", e(30, 0.7, 10.5, 0.2, item: 67, cup: 244)),
            ("avocado", e(160, 2, 8.5, 14.7, item: 150, cup: 150)),
            ("apple", e(52, 0.3, 14, 0.2, item: 182, cup: 125)),
            ("banana", e(89, 1.1, 23, 0.3, item: 118, cup: 150)),
            ("strawberry", e(32, 0.7, 7.7, 0.3, item: 12, cup: 152)),
            ("blueberry", e(57, 0.7, 14, 0.3, cup: 148)),
            ("berry", e(57, 0.7, 14, 0.3, cup: 148)),
            ("orange", e(47, 0.9, 12, 0.1, item: 131)),
            ("mango", e(60, 0.8, 15, 0.4, item: 336, cup: 165)),
            ("corn", e(86, 3.3, 19, 1.2, item: 90, cup: 145)),
            ("pea", e(81, 5.4, 14, 0.4, cup: 145)),
            ("green bean", e(31, 1.8, 7, 0.1, cup: 100)),
            ("cilantro", e(23, 2.1, 3.7, 0.5, cup: 16)),
            ("parsley", e(36, 3, 6.3, 0.8, cup: 60)),
            ("basil", e(23, 3.2, 2.7, 0.6, cup: 24)),
            // Legumes, nuts, seeds
            ("black bean", e(91, 6, 16, 0.3, item: 425, cup: 172)),
            ("kidney bean", e(127, 8.7, 22.8, 0.5, item: 425, cup: 177)),
            ("chickpea", e(139, 7.3, 22.5, 2.6, item: 425, cup: 164)),
            ("lentil", e(352, 25, 63, 1, cup: 192)),
            ("bean", e(127, 8.7, 22.8, 0.5, item: 425, cup: 177)),
            ("hummus", e(166, 8, 14, 10, cup: 246)),
            ("peanut butter", e(588, 25, 20, 50, cup: 258)),
            ("almond", e(579, 21, 22, 50, item: 1.2, cup: 143)),
            ("walnut", e(654, 15, 14, 65, cup: 117)),
            ("cashew", e(553, 18, 30, 44, cup: 137)),
            ("chia", e(486, 17, 42, 31, cup: 160)),
            ("sesame", e(573, 18, 23, 50, cup: 144)),
            // Pantry
            ("olive oil", e(884, 0, 0, 100, cup: 216)),
            ("coconut oil", e(892, 0, 0, 100, cup: 218)),
            ("sesame oil", e(884, 0, 0, 100, cup: 218)),
            ("oil", e(884, 0, 0, 100, cup: 218)),
            ("sugar", e(387, 0, 100, 0, cup: 200)),
            ("honey", e(304, 0.3, 82, 0, cup: 340)),
            ("maple syrup", e(260, 0, 67, 0, cup: 320)),
            ("soy sauce", e(53, 8, 5, 0, cup: 255)),
            ("broth", e(7, 1, 0.5, 0.2, cup: 240)),
            ("stock", e(7, 1, 0.5, 0.2, cup: 240)),
            ("vinegar", e(18, 0, 0.9, 0, cup: 240)),
            ("mayonnaise", e(680, 1, 0.6, 75, cup: 220)),
            ("ketchup", e(101, 1, 27, 0.1, cup: 240)),
            ("salsa", e(36, 1.5, 7, 0.2, cup: 260)),
            ("chocolate", e(480, 4, 63, 30, cup: 170)),
            ("salt", e(0, 0, 0, 0, cup: 292)),
            ("black pepper", e(251, 10, 64, 3, cup: 100)),
            ("cumin", e(375, 18, 44, 22, cup: 100)),
            ("paprika", e(282, 14, 54, 13, cup: 100)),
            ("curry powder", e(325, 14, 56, 14, cup: 100)),
            ("chili powder", e(282, 13, 50, 14, cup: 100)),
            ("oregano", e(265, 9, 69, 4, cup: 50)),
            ("cinnamon", e(247, 4, 81, 1, cup: 130)),
            ("water", e(0, 0, 0, 0, cup: 237))
        ]
        return raw
            .map { (IngredientNameMatcher.key($0.0).split(separator: " ").map(String.init), $0.1) }
            .filter { !$0.0.isEmpty }
            .sorted { $0.0.count > $1.0.count }
    }()
}

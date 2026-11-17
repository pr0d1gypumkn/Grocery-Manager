import Foundation

// MARK: - Food groups

/// Broad nutrition groups used to judge how varied a set of meals is.
enum FoodGroup: String, CaseIterable, Identifiable, Hashable {
    case vegetables = "Veg"
    case fruit = "Fruit"
    case protein = "Protein"
    case legumes = "Legumes"
    case grains = "Grains"
    case dairy = "Dairy"
    case healthyFats = "Healthy fats"

    var id: String { rawValue }

    /// The group an ingredient belongs to, or `nil` for staples and anything unrecognised.
    static func classify(_ name: String) -> FoodGroup? {
        let tokens = IngredientNameMatcher.key(name).split(separator: " ").map(String.init)
        guard !tokens.isEmpty, !PrepStaples.isStaple(tokens) else { return nil }
        // Rules are sorted longest phrase first, so "green bean" wins over "bean".
        return rules.first { tokens.containsPhrase($0.tokens) }?.group
    }

    private static let rules: [(tokens: [String], group: FoodGroup)] = {
        let raw: [FoodGroup: [String]] = [
            .vegetables: [
                "spinach", "kale", "broccoli", "carrot", "onion", "green onion", "shallot", "garlic",
                "ginger", "bell pepper", "pepper", "jalapeno", "chili", "tomato", "zucchini", "eggplant",
                "cucumber", "lettuce", "romaine", "arugula", "cabbage", "cauliflower", "mushroom", "celery",
                "asparagus", "squash", "pumpkin", "sweet potato", "potato", "beet", "corn", "peas",
                "snap pea", "green bean", "bok choy", "leek", "chard", "brussels sprouts", "okra",
                "radish", "fennel", "artichoke", "parsley", "cilantro", "basil", "mint", "salad greens"
            ],
            .fruit: [
                "apple", "banana", "berry", "blueberry", "strawberry", "raspberry", "blackberry", "lemon",
                "lime", "orange", "mango", "pineapple", "grape", "peach", "pear", "cherry", "kiwi", "date",
                "raisin", "cranberry", "pomegranate", "melon", "watermelon", "apricot", "plum", "fig"
            ],
            .protein: [
                "chicken", "beef", "pork", "turkey", "lamb", "fish", "salmon", "tuna", "cod", "tilapia",
                "shrimp", "prawn", "egg", "tofu", "tempeh", "seitan", "sausage", "bacon", "ham", "steak",
                "mince", "scallop", "crab", "sardine", "trout"
            ],
            .legumes: [
                "bean", "black bean", "kidney bean", "pinto bean", "lentil", "chickpea", "edamame",
                "hummus", "split pea"
            ],
            .grains: [
                "rice", "quinoa", "oat", "barley", "pasta", "spaghetti", "penne", "noodle", "bread",
                "tortilla", "couscous", "bulgur", "farro", "buckwheat", "millet", "pita"
            ],
            .dairy: [
                "milk", "yogurt", "yoghurt", "cheese", "feta", "parmesan", "mozzarella", "cheddar",
                "ricotta", "cottage cheese", "cream cheese", "kefir", "sour cream", "cream", "almond milk"
            ],
            .healthyFats: [
                "avocado", "almond", "walnut", "cashew", "peanut", "peanut butter", "pecan", "pistachio",
                "hazelnut", "nut", "seed", "chia", "flax", "sesame seed", "sunflower seed", "pumpkin seed",
                "tahini", "olive", "coconut milk"
            ]
        ]
        return raw
            .flatMap { group, phrases in
                phrases.map { (IngredientNameMatcher.key($0).split(separator: " ").map(String.init), group) }
            }
            .filter { !$0.0.isEmpty }
            .sorted { $0.0.count > $1.0.count }
    }()
}

/// Ingredients nearly every recipe uses. Sharing them saves no real prep, so they are ignored.
enum PrepStaples {
    private static let singleTokens: Set<String> = ["salt", "oil", "water", "sugar", "flour", "ice", "spray"]
    private static let phrases: [[String]] = [
        "black pepper", "pepper flakes", "baking soda", "baking powder", "salt and pepper"
    ].map { IngredientNameMatcher.key($0).split(separator: " ").map(String.init) }

    static func isStaple(_ tokens: [String]) -> Bool {
        tokens.contains { singleTokens.contains($0) } || phrases.contains { tokens.containsPhrase($0) }
    }

    static func isStaple(_ name: String) -> Bool {
        isStaple(IngredientNameMatcher.key(name).split(separator: " ").map(String.init))
    }
}

// MARK: - Cooking techniques

/// Cooking steps that can be done once for several recipes.
enum PrepTechnique: String, CaseIterable, Hashable {
    case oven, boil, grill, steam, blend, marinate, slowCook

    private var keywords: [String] {
        switch self {
        case .oven: ["roast", "bake", "oven", "broil"]
        case .boil: ["boil", "blanch"]
        case .grill: ["grill", "barbecue", "bbq"]
        case .steam: ["steam"]
        case .blend: ["blend", "food processor", "puree", "purée"]
        case .marinate: ["marinate", "marinade"]
        case .slowCook: ["slow cook", "slow-cook", "pressure cook", "instant pot", "crock"]
        }
    }

    var symbol: String {
        switch self {
        case .oven: "oven.fill"
        case .boil: "drop.degreesign.fill"
        case .grill: "flame.fill"
        case .steam: "humidity.fill"
        case .blend: "tornado"
        case .marinate: "timer"
        case .slowCook: "clock.fill"
        }
    }

    /// Techniques mentioned in a recipe's instructions.
    static func detect(in instructions: String) -> Set<PrepTechnique> {
        // A Dutch oven is a pot, not a reason to turn the oven on.
        let text = instructions.lowercased().replacingOccurrences(of: "dutch oven", with: "pot")
        return Set(allCases.filter { technique in technique.keywords.contains { text.contains($0) } })
    }

    /// Oven temperatures like "200°C" or "400 degrees F", normalised to "400°F".
    static func ovenTemperatures(in instructions: String) -> Set<String> {
        let pattern = #/(\d{3})\s*(?:°|º|degrees?)\s*([FfCc])?/#
        return Set(instructions.matches(of: pattern).map { match in
            let unit = match.output.2.map { String($0).uppercased() } ?? ""
            return "\(match.output.1)°\(unit)"
        })
    }
}

// MARK: - Results

/// One batch-prep step that serves several recipes, e.g. "Chop onion & garlic once".
struct PrepTask: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let recipeNames: [String]
}

struct MealPrepBundle<Item>: Identifiable {
    let id: String
    let items: [Item]
    /// Display names of non-staple ingredients used by at least two recipes.
    let sharedIngredients: [String]
    let tasks: [PrepTask]
    let groups: Set<FoodGroup>
    /// Distinct non-staple ingredients to shop for and prep across the bundle.
    let uniqueIngredientCount: Int
    /// What the count would be if every recipe were prepped on its own.
    let totalIngredientCount: Int
    let score: Double
}

struct PrepCompanion<Item>: Identifiable {
    let id: Int
    let item: Item
    let sharedIngredients: [String]
    let sharedTechniques: Set<PrepTechnique>
    /// Food groups this recipe adds that the original doesn't have.
    let addedGroups: Set<FoodGroup>
    let score: Double
}

// MARK: - Planner

/// Suggests sets of recipes that share ingredients and cooking steps (so they're quick to
/// prep together) while covering a wide range of food groups (so the week stays varied).
struct MealPrepPlanner<Item> {
    private struct Profile {
        let index: Int
        let name: String
        let instructions: String
        /// Ingredient key → display name, staples removed.
        let ingredients: [String: String]
        let groups: Set<FoodGroup>
        let techniques: Set<PrepTechnique>
        let ovenTemperatures: Set<String>
        let hasProduce: Bool
    }

    private let items: [Item]
    private let profiles: [Profile]

    init(
        items: [Item],
        name: (Item) -> String,
        ingredientNames: (Item) -> [String],
        instructions: (Item) -> String
    ) {
        self.items = items
        self.profiles = items.enumerated().compactMap { index, item in
            var ingredients: [String: String] = [:]
            var groups: Set<FoodGroup> = []
            for ingredientName in ingredientNames(item) {
                let key = IngredientNameMatcher.key(ingredientName)
                guard !key.isEmpty, !PrepStaples.isStaple(ingredientName) else { continue }
                ingredients[key] = ingredients[key] ?? ingredientName.trimmingCharacters(in: .whitespaces)
                if let group = FoodGroup.classify(ingredientName) { groups.insert(group) }
            }
            guard !ingredients.isEmpty else { return nil }
            let text = instructions(item)
            return Profile(
                index: index,
                name: name(item),
                instructions: text,
                ingredients: ingredients,
                groups: groups,
                techniques: PrepTechnique.detect(in: text),
                ovenTemperatures: PrepTechnique.ovenTemperatures(in: text),
                hasProduce: groups.contains(.vegetables) || groups.contains(.fruit)
            )
        }
    }

    // MARK: Bundles

    /// The best sets of `size` recipes to prep together, highest scoring first.
    /// When `anchor` matches an item, every bundle includes it.
    func bundles(size: Int, anchor: ((Item) -> Bool)? = nil, limit: Int = 5) -> [MealPrepBundle<Item>] {
        guard size >= 2, profiles.count >= size else { return [] }

        let seeds = anchor.map { isAnchor in profiles.filter { isAnchor(items[$0.index]) } } ?? profiles
        var seen: Set<[Int]> = []
        var results: [MealPrepBundle<Item>] = []

        for seed in seeds {
            var chosen = [seed]
            while chosen.count < size {
                let next = profiles
                    .filter { candidate in
                        !chosen.contains { $0.index == candidate.index } && sharesWork(candidate, with: chosen)
                    }
                    .max { score(chosen + [$0]) < score(chosen + [$1]) }
                guard let next else { break }
                chosen.append(next)
            }
            let key = chosen.map(\.index).sorted()
            guard chosen.count == size, seen.insert(key).inserted else { continue }
            results.append(makeBundle(chosen))
        }

        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }

    // MARK: Companions

    /// Recipes that pair well with `item` for prep, highest scoring first.
    func companions(for isTarget: (Item) -> Bool, limit: Int = 3) -> [PrepCompanion<Item>] {
        guard let target = profiles.first(where: { isTarget(items[$0.index]) }) else { return [] }

        return profiles
            .filter { $0.index != target.index }
            .compactMap { other -> PrepCompanion<Item>? in
                let sharedKeys = Set(target.ingredients.keys).intersection(other.ingredients.keys)
                let sharedTechniques = target.techniques.intersection(other.techniques)
                guard !sharedKeys.isEmpty || !sharedTechniques.isEmpty else { return nil }
                let added = other.groups.subtracting(target.groups)
                let score = 2 * Double(sharedKeys.count)
                    + 1.5 * Double(sharedTechniques.count)
                    + Double(added.count)
                    - (Self.isNearDuplicate(target, other) ? 5 : 0)
                return PrepCompanion(
                    id: other.index,
                    item: items[other.index],
                    sharedIngredients: sharedKeys.compactMap { other.ingredients[$0] }.sorted(),
                    sharedTechniques: sharedTechniques,
                    addedGroups: added,
                    score: score
                )
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Scoring

    private func sharesWork(_ candidate: Profile, with chosen: [Profile]) -> Bool {
        chosen.contains { profile in
            !Set(profile.ingredients.keys).isDisjoint(with: candidate.ingredients.keys)
                || !profile.techniques.isDisjoint(with: candidate.techniques)
        }
    }

    /// Rewards shared prep and food-group variety; penalises near-identical meals.
    private func score(_ profiles: [Profile]) -> Double {
        let sharedIngredientWork = Self.counts(profiles.flatMap(\.ingredients.keys)).values.reduce(0) { $0 + max($1 - 1, 0) }
        let sharedTechniqueWork = Self.counts(profiles.flatMap(\.techniques)).values.reduce(0) { $0 + max($1 - 1, 0) }
        let variety = profiles.reduce(into: Set<FoodGroup>()) { $0.formUnion($1.groups) }.count
        let produceMeals = profiles.filter(\.hasProduce).count

        var duplicates = 0
        for i in profiles.indices {
            for j in profiles.indices where j > i && Self.isNearDuplicate(profiles[i], profiles[j]) {
                duplicates += 1
            }
        }

        return 2 * Double(sharedIngredientWork)
            + 1.5 * Double(sharedTechniqueWork)
            + 1.5 * Double(variety)
            + 0.5 * Double(produceMeals)
            - 5 * Double(duplicates)
    }

    /// Two recipes with mostly the same ingredients make for a monotonous week.
    private static func isNearDuplicate(_ a: Profile, _ b: Profile) -> Bool {
        let left = Set(a.ingredients.keys), right = Set(b.ingredients.keys)
        let union = left.union(right).count
        guard union > 0 else { return false }
        return Double(left.intersection(right).count) / Double(union) >= 0.75
    }

    private static func counts<T: Hashable>(_ values: [T]) -> [T: Int] {
        values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    // MARK: Building results

    private func makeBundle(_ chosen: [Profile]) -> MealPrepBundle<Item> {
        let keyCounts = Self.counts(chosen.flatMap(\.ingredients.keys))
        let sharedKeys = keyCounts.filter { $0.value >= 2 }.map(\.key).sorted()
        let displayName: (String) -> String = { key in
            chosen.lazy.compactMap { $0.ingredients[key] }.first ?? key
        }

        return MealPrepBundle(
            id: chosen.map { String($0.index) }.sorted().joined(separator: "-"),
            items: chosen.map { items[$0.index] },
            sharedIngredients: sharedKeys.map(displayName),
            tasks: tasks(for: chosen, sharedKeys: sharedKeys, displayName: displayName),
            groups: chosen.reduce(into: Set<FoodGroup>()) { $0.formUnion($1.groups) },
            uniqueIngredientCount: keyCounts.count,
            totalIngredientCount: keyCounts.values.reduce(0, +),
            score: score(chosen)
        )
    }

    private func tasks(
        for chosen: [Profile],
        sharedKeys: [String],
        displayName: (String) -> String
    ) -> [PrepTask] {
        var batchCook: [PrepTask] = []
        var knifeWork: [String: [(name: String, recipes: Set<String>)]] = [:]
        var assemble: [(name: String, recipes: Set<String>)] = []

        for key in sharedKeys {
            let users = chosen.filter { $0.ingredients[key] != nil }
            let name = displayName(key).lowercased()
            let recipeNames = Set(users.map(\.name))

            switch FoodGroup.classify(name) {
            case .protein, .grains, .legumes:
                batchCook.append(PrepTask(
                    id: "cook-\(key)",
                    title: "Cook all the \(name) in one batch",
                    symbol: "frying.pan.fill",
                    recipeNames: recipeNames.sorted()
                ))
            case .vegetables:
                let verb = Self.knifeVerb(for: key, in: users.map(\.instructions))
                knifeWork[verb, default: []].append((name, recipeNames))
            default:
                assemble.append((name, recipeNames))
            }
        }

        var techniqueTasks: [PrepTask] = []
        for technique in PrepTechnique.allCases {
            let users = chosen.filter { $0.techniques.contains(technique) }
            guard users.count >= 2 else { continue }
            techniqueTasks.append(PrepTask(
                id: "technique-\(technique.rawValue)",
                title: Self.title(for: technique, temperatures: users.reduce(into: Set<String>()) { $0.formUnion($1.ovenTemperatures) }),
                symbol: technique.symbol,
                recipeNames: users.map(\.name).sorted()
            ))
        }

        let knifeTasks = knifeWork.keys.sorted().map { verb -> PrepTask in
            let entries = knifeWork[verb] ?? []
            return PrepTask(
                id: "knife-\(verb)",
                title: "\(verb) \(Self.list(entries.map(\.name))) once",
                symbol: "carrot.fill",
                recipeNames: entries.reduce(into: Set<String>()) { $0.formUnion($1.recipes) }.sorted()
            )
        }

        var result = batchCook + techniqueTasks + knifeTasks
        if !assemble.isEmpty {
            result.append(PrepTask(
                id: "portion",
                title: "Portion out \(Self.list(assemble.map(\.name))) together",
                symbol: "square.split.2x2.fill",
                recipeNames: assemble.reduce(into: Set<String>()) { $0.formUnion($1.recipes) }.sorted()
            ))
        }
        return result
    }

    private static func title(for technique: PrepTechnique, temperatures: Set<String>) -> String {
        switch technique {
        case .oven:
            switch temperatures.count {
            case 0: return "Share one oven session"
            case 1: return "Share one oven session at \(temperatures.first!)"
            default: return "Share the oven: start at \(temperatures.sorted().first!), then raise to \(temperatures.sorted().last!)"
            }
        case .boil: return "Boil one big pot of water for everything"
        case .grill: return "Fire up the grill once"
        case .steam: return "Steam everything in one go"
        case .blend: return "Blend sauces back-to-back (rinse between)"
        case .marinate: return "Mix the marinades the night before"
        case .slowCook: return "Queue the slow-cooker / pressure-cooker batches"
        }
    }

    private static var knifeVerbs: [(word: String, verb: String)] {
        [
            ("dice", "Dice"), ("mince", "Mince"), ("chop", "Chop"), ("slice", "Slice"),
            ("grate", "Grate"), ("shred", "Shred"), ("julienne", "Julienne"), ("peel", "Peel")
        ]
    }

    /// Finds how the recipes cut an ingredient, e.g. "Dice" from "dice the onion".
    private static func knifeVerb(for key: String, in instructions: [String]) -> String {
        let anchor = key.split(separator: " ").last.map(String.init) ?? key
        let sentences = instructions
            .flatMap { $0.lowercased().split(whereSeparator: { ".\n;!".contains($0) }) }
            .filter { $0.contains(anchor) }
        for (word, verb) in knifeVerbs where sentences.contains(where: { $0.contains(word) }) {
            return verb
        }
        return "Wash & chop"
    }

    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " & " + names.last!
        }
    }
}

extension MealPrepPlanner where Item == Recipe {
    init(recipes: [Recipe]) {
        self.init(
            items: recipes,
            name: \.name,
            ingredientNames: { $0.ingredients.map(\.name) },
            instructions: \.instructions
        )
    }
}


import Foundation

// MARK: - Plan types (Codable, stored on PrepSession)

/// Which "station" a step occupies. Only one hands-on lane can be used per person at a
/// time; passive steps (marinating, preheating, resting) run alongside anything.
enum PrepLane: String, Codable, CaseIterable, Identifiable {
    case prep, stove, oven, passive, assemble

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prep: "Knife work"
        case .stove: "Stovetop"
        case .oven: "Oven"
        case .passive: "Hands-off"
        case .assemble: "Assemble"
        }
    }

    var symbol: String {
        switch self {
        case .prep: "carrot.fill"
        case .stove: "frying.pan.fill"
        case .oven: "oven.fill"
        case .passive: "timer"
        case .assemble: "square.split.2x2.fill"
        }
    }

    var defaultMinutes: Int {
        switch self {
        case .prep: 5
        case .stove: 10
        case .oven: 20
        case .passive: 15
        case .assemble: 5
        }
    }

    var isHandsOn: Bool { self != .passive }
}

struct PrepStep: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    var detail: String = ""
    var lane: PrepLane
    var minutes: Int
    /// Set when the step has a cook/rest time worth a countdown.
    var timerMinutes: Int?
    var recipeNames: [String]
    /// Steps sharing a group index are done at the same time.
    var group: Int = 0
    /// Lemmatised operations ("dice", "simmer") and ingredient keys of a recipe step.
    /// Optional so plans stored before these existed still decode.
    var operations: [String]? = nil
    var ingredients: [String]? = nil
}

struct PrepRecipeSummary: Codable, Equatable, Hashable {
    var name: String
    var servings: Int
}

struct PrepPlan: Codable, Equatable {
    var steps: [PrepStep]
    var recipes: [PrepRecipeSummary]
    var estimatedMinutes: Int

    var groups: [[PrepStep]] {
        Dictionary(grouping: steps, by: \.group)
            .sorted { $0.key < $1.key }
            .map(\.value)
    }

    var timers: [PrepStep] { steps.filter { $0.timerMinutes != nil } }
}

// MARK: - Input

struct PrepRecipeInput {
    var name: String
    var instructions: String
    var ingredientNames: [String]
    var servings: Int
    /// Stored lemmatised steps and ingredient keys; computed from the text when nil.
    var steps: [RecipeStep]? = nil
    var ingredientKeys: [String]? = nil

    var resolvedKeys: [String] {
        ingredientKeys ?? ingredientNames.map(IngredientNameMatcher.key).filter { !$0.isEmpty }
    }

    var resolvedSteps: [RecipeStep] {
        steps ?? StepLemmatizer.steps(from: instructions, ingredientKeys: resolvedKeys)
    }
}

// MARK: - Planner

/// Turns several recipes into one batch-cooking session: shared knife work and batch cooks
/// first, then each recipe's own steps interleaved so different stations run in parallel.
struct PrepSessionPlanner {
    /// How many hands-on steps one cook can juggle at once.
    var maxParallelHandsOn = 3

    func plan(_ inputs: [PrepRecipeInput]) -> PrepPlan {
        let recipes = inputs.filter { !$0.name.isEmpty }
        guard !recipes.isEmpty else { return PrepPlan(steps: [], recipes: [], estimatedMinutes: 0) }

        let shared = sharedSteps(for: recipes)
        let covered = Set(shared.flatMap(\.covers))
        var allSteps: [PrepStep] = []
        var nextGroup = 0

        // Shared work first: a single track, so knife tasks happen one after another, while
        // passive steps like preheating ride along.
        (allSteps, nextGroup) = schedule(tracks: [shared.map(\.step)], startingAt: 0)

        let tracks = recipes.map { recipe in
            recipeSteps(for: recipe, covered: covered)
        }
        let (recipeScheduled, _) = schedule(tracks: tracks, startingAt: nextGroup)
        allSteps += recipeScheduled

        let estimated = Dictionary(grouping: allSteps, by: \.group).values.reduce(0) { total, group in
            let handsOn = group.filter(\.lane.isHandsOn).map(\.minutes).max()
            let passive = group.map(\.minutes).max() ?? 0
            return total + (handsOn ?? passive)
        }

        return PrepPlan(
            steps: allSteps,
            recipes: recipes.map { PrepRecipeSummary(name: $0.name, servings: $0.servings) },
            estimatedMinutes: estimated
        )
    }

    // MARK: Shared work

    private struct SharedStep {
        var step: PrepStep
        /// The (operation family, ingredient) work this step does for every recipe, so
        /// per-recipe steps doing only that work can be skipped.
        var covers: [StepAction]
    }

    private func sharedSteps(for recipes: [PrepRecipeInput]) -> [SharedStep] {
        struct Usage { var display: String; var recipes: [String] }
        var usage: [String: Usage] = [:]
        for recipe in recipes {
            var seen: Set<String> = []
            for name in recipe.ingredientNames {
                let key = IngredientNameMatcher.key(name)
                guard !key.isEmpty, !PrepStaples.isStaple(name), seen.insert(key).inserted else { continue }
                usage[key, default: Usage(display: name.trimmingCharacters(in: .whitespaces).lowercased(), recipes: [])].recipes.append(recipe.name)
            }
        }
        let sharedKeys = usage.filter { $0.value.recipes.count >= 2 }.keys.sorted()

        var result: [SharedStep] = []
        var knifeWork: [String: [(key: String, display: String, recipes: [String])]] = [:]

        for key in sharedKeys {
            guard let entry = usage[key] else { continue }
            switch FoodGroup.classify(entry.display) {
            case .protein, .grains, .legumes:
                result.append(SharedStep(
                    step: PrepStep(
                        id: "shared-cook-\(key)",
                        title: "Cook all the \(entry.display) in one batch",
                        detail: "Enough for \(entry.recipes.joined(separator: ", ")).",
                        lane: .stove,
                        minutes: 15,
                        timerMinutes: 15,
                        recipeNames: entry.recipes
                    ),
                    covers: [StepAction(family: "boil", ingredient: key)]
                ))
            case .vegetables:
                let verb = knifeVerb(for: key, in: recipes.filter { entry.recipes.contains($0.name) }.flatMap(\.resolvedSteps))
                knifeWork[verb, default: []].append((key, entry.display, entry.recipes))
            default:
                continue
            }
        }

        for verb in knifeWork.keys.sorted() {
            let items = knifeWork[verb] ?? []
            let recipeNames = Array(Set(items.flatMap(\.recipes))).sorted()
            result.insert(SharedStep(
                step: PrepStep(
                    id: "shared-knife-\(verb.lowercased())",
                    title: "\(verb) \(Self.list(items.map(\.display))) for everything",
                    detail: "Used by \(recipeNames.joined(separator: ", ")). Keep each in its own container.",
                    lane: .prep,
                    minutes: 3 * items.count,
                    recipeNames: recipeNames
                ),
                covers: items.flatMap { item in
                    Self.knifeFamilies(for: verb).map { StepAction(family: $0, ingredient: item.key) }
                }
            ), at: 0)
        }

        // One oven preheat for the whole session.
        let ovenRecipes = recipes.filter { PrepTechnique.detect(in: $0.instructions).contains(.oven) }
        if !ovenRecipes.isEmpty {
            let temperatures = ovenRecipes.reduce(into: Set<String>()) { $0.formUnion(PrepTechnique.ovenTemperatures(in: $1.instructions)) }
            let title = temperatures.count == 1 ? "Preheat the oven to \(temperatures.first!)" : "Preheat the oven"
            result.insert(SharedStep(
                step: PrepStep(
                    id: "shared-preheat",
                    title: title,
                    detail: temperatures.count > 1 ? "Recipes need \(temperatures.sorted().joined(separator: " and ")); start low and raise it." : "",
                    lane: .passive,
                    minutes: 10,
                    timerMinutes: 10,
                    recipeNames: ovenRecipes.map(\.name)
                ),
                covers: []
            ), at: 0)
        }
        return result
    }

    // MARK: Per-recipe steps

    private func recipeSteps(for recipe: PrepRecipeInput, covered: Set<StepAction>) -> [PrepStep] {
        var steps: [PrepStep] = []
        for (index, recipeStep) in recipe.resolvedSteps.enumerated() {
            let sentence = recipeStep.text
            let lane = Self.lane(for: sentence)
            if lane == .passive, recipeStep.operations.contains("preheat") || sentence.lowercased().contains("preheat") { continue } // handled once for the session
            // Everything this step does already happens in a shared step.
            let actions = recipeStep.actions
            if !actions.isEmpty, actions.isSubset(of: covered) { continue }
            let parsed = Self.minutes(in: sentence)
            let minutes = parsed ?? lane.defaultMinutes
            steps.append(PrepStep(
                id: "\(recipe.name)-\(index)",
                title: sentence,
                lane: lane,
                minutes: minutes,
                timerMinutes: (parsed != nil && lane != .prep && lane != .assemble && minutes >= 2) ? minutes : nil,
                recipeNames: [recipe.name],
                operations: recipeStep.operations,
                ingredients: recipeStep.ingredients
            ))
        }
        if steps.isEmpty {
            steps.append(PrepStep(
                id: "\(recipe.name)-cook",
                title: "Cook \(recipe.name)",
                lane: .stove,
                minutes: 20,
                timerMinutes: nil,
                recipeNames: [recipe.name]
            ))
        }
        steps.append(PrepStep(
            id: "\(recipe.name)-portion",
            title: "Portion \(recipe.name) into containers and label them",
            lane: .assemble,
            minutes: 4,
            timerMinutes: nil,
            recipeNames: [recipe.name]
        ))
        return steps
    }

    // MARK: Scheduling

    /// Round-robin across tracks: each group takes at most one step per track and at most one
    /// hands-on step per lane, so a stove step and a knife step can share a group, two stove
    /// steps can't. A track's steps always stay in order.
    private func schedule(tracks: [[PrepStep]], startingAt firstGroup: Int) -> ([PrepStep], Int) {
        var pointers = Array(repeating: 0, count: tracks.count)
        var group = firstGroup
        var scheduled: [PrepStep] = []

        while zip(pointers, tracks).contains(where: { $0 < $1.count }) {
            var usedLanes: Set<PrepLane> = []
            var handsOn = 0
            var placedAny = false
            for trackIndex in tracks.indices where pointers[trackIndex] < tracks[trackIndex].count {
                var step = tracks[trackIndex][pointers[trackIndex]]
                if step.lane.isHandsOn {
                    guard !usedLanes.contains(step.lane), handsOn < maxParallelHandsOn else { continue }
                    usedLanes.insert(step.lane)
                    handsOn += 1
                }
                step.group = group
                scheduled.append(step)
                pointers[trackIndex] += 1
                placedAny = true
            }
            if !placedAny {
                // Every remaining head conflicts on lane; force the first one through.
                if let trackIndex = tracks.indices.first(where: { pointers[$0] < tracks[$0].count }) {
                    var step = tracks[trackIndex][pointers[trackIndex]]
                    step.group = group
                    scheduled.append(step)
                    pointers[trackIndex] += 1
                }
            }
            group += 1
        }
        return (scheduled, group)
    }

    // MARK: Text helpers

    static func lane(for sentence: String) -> PrepLane {
        let text = sentence.lowercased().replacingOccurrences(of: "dutch oven", with: "pot")
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        if has(["preheat"]) && !has(["bake", "roast", "broil"]) { return .passive }
        if has(["bake", "roast", "broil", "in the oven", "into the oven"]) { return .oven }
        if has(["boil", "simmer", "saut", "fry", "sear", "brown the", "skillet", "saucepan", "pot", "wok", "grill", "steam", "pressure cook", "slow cook", "heat the oil", "heat oil", "over medium", "over high", "over low", "cook until", "cook for", "cook the", "toast", "melt", "reduce", "stir-fry", "stir fry", "scramble", "poach", "braise", "deglaze"]) { return .stove }
        if has(["marinate", "let rest", "let it rest", "rest for", "chill", "refrigerate", "let cool", "cool completely", "let sit", "let stand", "rise", "soak", "freeze", "overnight", "steep"]) { return .passive }
        if has(["chop", "dice", "slice", "mince", "peel", "wash", "grate", "cut ", "trim", "shred", "zest", "halve", "quarter", "crush", "rinse", "drain", "cube", "julienne", "core", "deseed", "pat dry"]) { return .prep }
        return .assemble
    }

    static func minutes(in sentence: String) -> Int? {
        let text = sentence.lowercased()
        if text.contains("overnight") { return 480 }
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:(?:-|–|to)\s*(\d+(?:\.\d+)?))?\s*(minutes?|mins?|hours?|hrs?|h\b|m\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        var longest: Int?
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let lowRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 3), in: text),
                  let low = Double(text[lowRange]) else { continue }
            let high = Range(match.range(at: 2), in: text).flatMap { Double(text[$0]) } ?? low
            let unit = text[unitRange]
            let multiplier = unit.hasPrefix("h") ? 60.0 : 1.0
            let value = Int((max(low, high) * multiplier).rounded())
            longest = max(longest ?? 0, value)
        }
        return longest
    }

    private static let knifeVerbs = ["dice", "mince", "chop", "slice", "cube", "grate", "shred", "julienne", "zest", "peel"]

    /// The knife operation the recipes apply to this ingredient most often.
    private func knifeVerb(for key: String, in steps: [RecipeStep]) -> String {
        var counts: [String: Int] = [:]
        for step in steps where step.ingredients.contains(key) {
            for op in step.operations where Self.knifeVerbs.contains(op) { counts[op, default: 0] += 1 }
        }
        let best = Self.knifeVerbs.filter { counts[$0] != nil }.max { counts[$0]! < counts[$1]! || (counts[$0]! == counts[$1]! && Self.knifeVerbs.firstIndex(of: $0)! > Self.knifeVerbs.firstIndex(of: $1)!) }
        return best?.capitalized ?? "Wash & chop"
    }

    /// The operation families a shared knife step takes care of.
    private static func knifeFamilies(for verb: String) -> [String] {
        let op = verb.lowercased()
        guard knifeVerbs.contains(op) else { return ["cut", "clean"] }
        return Array(Set([CookingOperation.family(of: op), "clean"]))
    }

    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " & " + names.last!
        }
    }
}

/// Splits recipe instructions into individual steps: one per line when the recipe is
/// written that way, otherwise one per sentence.
enum InstructionSteps {
    static func split(_ instructions: String) -> [String] {
        let lines = instructions
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"^\s*(?:step\s*)?\d+[.):]\s*"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count > 1 { return lines }
        guard let text = lines.first else { return [] }

        var sentences: [String] = []
        (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (text as NSString).length), options: [.bySentences, .localized]) { substring, _, _, _ in
            let trimmed = substring?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return }
            if trimmed.count < 15, !sentences.isEmpty {
                sentences[sentences.count - 1] += " " + trimmed
            } else {
                sentences.append(trimmed)
            }
        }
        return sentences
    }
}

extension PrepSessionPlanner {
    /// Builds the plan for a set of planned meals, grouping entries of the same recipe.
    static func inputs(for entries: [MealPlanEntry]) -> [PrepRecipeInput] {
        var order: [String] = []
        var byRecipe: [String: PrepRecipeInput] = [:]
        for entry in entries {
            guard let recipe = entry.recipe else { continue }
            if var existing = byRecipe[recipe.name] {
                existing.servings += entry.servings
                byRecipe[recipe.name] = existing
            } else {
                order.append(recipe.name)
                byRecipe[recipe.name] = PrepRecipeInput(
                    name: recipe.name,
                    instructions: recipe.instructions,
                    ingredientNames: recipe.ingredients.map(\.name),
                    servings: entry.servings,
                    steps: recipe.lemmatizedSteps,
                    ingredientKeys: recipe.ingredientKeys
                )
            }
        }
        return order.compactMap { byRecipe[$0] }
    }
}

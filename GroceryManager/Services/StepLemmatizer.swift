import Foundation
import SwiftData

// MARK: - Stored step

/// One recipe step reduced to what it does: the cooking operations in it, lemmatised
/// ("Chopping" → "chop", "stir-fried" → "stir-fry"), and the recipe ingredients it mentions,
/// as `IngredientNameMatcher` keys. Two steps overlap when they apply an operation of the
/// same family to the same ingredient, e.g. "dice the onion" and "finely chop onions".
struct RecipeStep: Codable, Equatable, Hashable {
    var text: String
    var operations: [String]
    var ingredients: [String]

    /// (operation family, ingredient) pairs, the unit of overlap between steps.
    var actions: Set<StepAction> {
        Set(operations.flatMap { op in ingredients.map { StepAction(family: CookingOperation.family(of: op), ingredient: $0) } })
    }

    func overlaps(_ other: RecipeStep) -> Bool {
        !actions.isDisjoint(with: other.actions)
    }
}

struct StepAction: Hashable, Codable {
    var family: String
    var ingredient: String
}

// MARK: - Operation vocabulary

enum CookingOperation {
    /// Canonical operation → the family used to decide whether two steps do the same work.
    static let families: [String: String] = {
        let groups: [String: [String]] = [
            "cut": ["chop", "dice", "mince", "slice", "cube", "julienne", "cut", "halve", "quarter", "crush", "smash"],
            "grate": ["grate", "shred", "zest", "spiralize", "grind"],
            "clean": ["wash", "rinse", "peel", "trim", "core", "deseed", "pit", "pat dry", "scrub", "hull", "stem"],
            "boil": ["cook", "boil", "simmer", "steam", "poach", "blanch", "parboil", "pressure cook", "slow cook"],
            "fry": ["saute", "fry", "stir-fry", "sear", "brown", "scramble", "caramelize", "sweat"],
            "roast": ["roast", "bake", "broil", "air fry"],
            "grill": ["grill", "toast", "char", "barbecue"],
            "melt": ["melt", "reduce", "thicken"],
            "braise": ["braise", "deglaze", "stew"],
            "heat": ["heat", "preheat", "warm", "reheat"],
            "rest": ["marinate", "rest", "chill", "refrigerate", "cool", "freeze", "soak", "steep", "rise", "proof", "thaw", "defrost"],
            "mix": ["mix", "stir", "whisk", "beat", "fold", "toss", "combine", "blend", "puree", "knead", "add", "whip", "emulsify"],
            "season": ["season", "coat", "dredge", "sprinkle", "garnish", "drizzle", "brush", "glaze", "salt", "dress"],
            "mash": ["mash", "squeeze", "press"],
            "strain": ["strain", "drain", "sift", "skim"],
            "shape": ["roll", "shape", "form", "stuff", "wrap", "layer", "spread", "fill", "skewer", "thread"],
            "serve": ["serve", "assemble", "portion", "plate", "divide", "transfer", "pour", "top", "cover"]
        ]
        var map: [String: String] = [:]
        for (family, ops) in groups { ops.forEach { map[$0] = family } }
        return map
    }()

    static func family(of operation: String) -> String { families[operation] ?? operation }

    /// Words that are often nouns or adjectives ("golden brown", "over medium heat", "a
    /// quarter cup"): only counted in imperative position, at the start of a clause.
    static let ambiguous: Set<String> = [
        "brown", "cool", "rest", "core", "quarter", "cube", "rise", "beat", "toast", "cover",
        "heat", "top", "salt", "press", "form", "roll", "stem", "pit", "fill", "warm", "dress",
        "stew", "char", "plate", "thread", "proof", "layer", "glaze", "brush", "wrap", "spread",
        "cook", "mix", "steam", "drizzle", "divide", "season", "smash", "shape", "stuff", "cut"
    ]

    /// Irregular inflections → (canonical, is past participle).
    private static let irregular: [String: (String, Bool)] = [
        "froze": ("freeze", true), "frozen": ("freeze", true),
        "rose": ("rise", true), "risen": ("rise", true),
        "beaten": ("beat", true),
        "ground": ("grind", true),
        "sauteed": ("saute", true), "sauted": ("saute", true), "sauteing": ("saute", false), "sautes": ("saute", false),
        "barbecued": ("barbecue", true), "barbecuing": ("barbecue", false),
        "puréed": ("puree", true), "pureed": ("puree", true), "pureeing": ("puree", false),
        "dried": ("dry", true), "drying": ("dry", false),
        "fried": ("fry", true), "frying": ("fry", false), "fries": ("fry", false),
        "cut": ("cut", false), "cuts": ("cut", false), "cutting": ("cut", false)
    ]

    /// Single-syllable verbs that double their last consonant ("chop" → "chopped").
    private static let doubling: Set<String> = ["chop", "stir", "trim", "whip", "pat", "strip", "scrub", "skim", "pit", "stem", "top", "wrap"]

    /// Every inflected form of a single-word operation → (canonical, is past participle).
    static let forms: [String: (String, Bool)] = {
        var map: [String: (String, Bool)] = [:]
        // "dry" only so "pat dry" is recognised; it isn't an operation on its own.
        let singleWord = families.keys.filter { !$0.contains(" ") && !$0.contains("-") } + ["dry"]
        for verb in singleWord {
            map[verb] = (verb, false)
            let stem: String
            if doubling.contains(verb) {
                stem = verb + String(verb.last!)
            } else {
                stem = verb
            }
            if verb.hasSuffix("e") && !verb.hasSuffix("ee") {
                map[verb + "s"] = (verb, false)
                map[String(verb.dropLast()) + "ing"] = (verb, false)
                map[verb + "d"] = (verb, true)
            } else if verb.hasSuffix("y"), let before = verb.dropLast().last, !"aeiou".contains(before) {
                let root = String(verb.dropLast())
                map[root + "ies"] = (verb, false)
                map[verb + "ing"] = (verb, false)
                map[root + "ied"] = (verb, true)
            } else {
                let sibilant = ["s", "sh", "ch", "x", "z"].contains { verb.hasSuffix($0) }
                map[verb + (sibilant ? "es" : "s")] = (verb, false)
                map[stem + "ing"] = (verb, false)
                map[stem + "ed"] = (verb, true)
            }
        }
        for (form, value) in irregular { map[form] = value }
        return map
    }()
}

// MARK: - Lemmatiser

enum StepLemmatizer {
    /// Words that may sit between a clause boundary and its verb ("then gently fold").
    private static let leadIns: Set<String> = ["then", "next", "finally", "meanwhile", "also", "now", "first", "again", "immediately", "quickly", "and", "or", "just", "carefully", "gently", "lightly", "finely", "roughly", "thinly", "coarsely", "well", "once", "while", "you", "to", "let", "allow", "please"]
    /// Words after which an -ing form is still the action ("keep stirring", "while cooking").
    private static let beforeGerund: Set<String> = ["while", "keep", "continue", "continuing", "start", "begin", "before", "after", "by", "without", "finish", "stop", "until", "when", "then", "is", "are", "be", "been"]
    /// Words that may follow a past participle that is still an action ("browned on all sides").
    private static let afterParticiple: Set<String> = ["until", "for", "in", "with", "and", "through", "on", "over", "about", "to", "at", "into", "under", "by", "then", "or", "before", "while", "off"]

    /// All operations in a step, lemmatised and in order of appearance, without repeats.
    static func operations(in text: String) -> [String] {
        let words = tokenize(text)
        var result: [String] = []
        var index = 0
        func emit(_ op: String) { if !result.contains(op) { result.append(op) } }

        while index < words.count {
            let word = words[index]
            let next = index + 1 < words.count ? words[index + 1] : nil

            // Multi-word operations.
            if let next, let nextForm = CookingOperation.forms[next.text]?.0 {
                let phrase: String? = switch (word.text, nextForm) {
                case ("stir", "fry"): "stir-fry"
                case ("pan", "fry"), ("deep", "fry"), ("shallow", "fry"): "fry"
                case ("air", "fry"): "air fry"
                case ("pat", "dry"): "pat dry"
                case ("pre", "heat"): "preheat"
                case ("re", "heat"): "reheat"
                case ("par", "boil"): "parboil"
                case ("pressure", "cook"): "pressure cook"
                case ("slow", "cook"): "slow cook"
                default: nil
                }
                if let phrase {
                    emit(phrase)
                    index += 2
                    continue
                }
            }

            if let form = CookingOperation.forms[word.text], CookingOperation.families[form.0] != nil {
                let (op, isParticiple) = form
                let atClauseStart = isClauseStart(at: index, in: words)
                if isParticiple {
                    // "chopped onion" describes an ingredient; "browned on all sides" is an action.
                    let adjectival = next.map { !$0.followsBoundary && !afterParticiple.contains($0.text) } ?? false
                    if !adjectival { emit(op) }
                } else if word.text.hasSuffix("ing") && word.text != op {
                    // "baking sheet", "mixing bowl", "the dressing" are things, not actions.
                    let previous = index > 0 ? words[index - 1].text : nil
                    if atClauseStart || previous.map(beforeGerund.contains) == true { emit(op) }
                } else if !CookingOperation.ambiguous.contains(op) || atClauseStart {
                    emit(op)
                }
            }
            index += 1
        }
        return result
    }

    /// The recipe ingredients a step mentions, as matcher keys. A multi-word key matches when
    /// all its words appear or its head noun does ("chicken thigh" ← "the thighs"); failing
    /// that, its first word may stand in ("the chicken") when no other ingredient claims it.
    static func ingredients(in text: String, keys: [String]) -> [String] {
        let tokens = Set(IngredientNameMatcher.lemmaTokens(text))
        guard !tokens.isEmpty else { return [] }
        let candidates = Array(Set(keys.filter { !$0.isEmpty })).sorted()

        var found: [String] = []
        var claimed: Set<String> = []
        for key in candidates {
            let parts = key.split(separator: " ").map(String.init)
            guard let head = parts.last else { continue }
            if parts.allSatisfy(tokens.contains) || tokens.contains(head) {
                found.append(key)
                claimed.formUnion(parts)
            }
        }
        var byFirstWord: [String: [String]] = [:]
        for key in candidates where !found.contains(key) {
            let parts = key.split(separator: " ").map(String.init)
            guard parts.count > 1, let first = parts.first, first.count >= 4, tokens.contains(first), !claimed.contains(first) else { continue }
            byFirstWord[first, default: []].append(key)
        }
        for (_, keys) in byFirstWord where keys.count == 1 { found.append(keys[0]) }
        return found.sorted()
    }

    static func steps(from instructions: String, ingredientKeys: [String]) -> [RecipeStep] {
        InstructionSteps.split(instructions).map { text in
            RecipeStep(text: text, operations: operations(in: text), ingredients: ingredients(in: text, keys: ingredientKeys))
        }
    }

    /// Stable fingerprint of the inputs to `steps(from:ingredientKeys:)` (FNV-1a), so stored
    /// steps can be checked for staleness. Bump `version` when the lemmatiser changes.
    static let version = 1
    static func sourceHash(instructions: String, ingredientKeys: [String]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let input = "\(version)\u{1}\(instructions)\u{1}\(ingredientKeys.sorted().joined(separator: "\u{2}"))"
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    // MARK: Tokens

    private struct Word {
        var text: String
        /// Punctuation (or the start of the text) comes right before this word.
        var followsBoundary: Bool
    }

    private static func tokenize(_ text: String) -> [Word] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var words: [Word] = []
        var current = ""
        var boundary = true
        for character in folded {
            if character.isLetter {
                current.append(character)
            } else {
                if !current.isEmpty {
                    words.append(Word(text: current, followsBoundary: boundary))
                    current = ""
                    boundary = false
                }
                if ",;:.!?()\n".contains(character) { boundary = true }
            }
        }
        if !current.isEmpty { words.append(Word(text: current, followsBoundary: boundary)) }
        return words
    }

    private static func isClauseStart(at index: Int, in words: [Word]) -> Bool {
        var i = index
        while i >= 0 {
            if words[i].followsBoundary { return true }
            let previous = words[i - 1].text
            guard leadIns.contains(previous) || previous.hasSuffix("ly") else { return false }
            i -= 1
        }
        return true
    }
}

// MARK: - Recipe access

extension Recipe {
    var ingredientKeys: [String] { ingredients.map(\.lemmaKey).filter { !$0.isEmpty } }

    /// The lemmatised steps, from storage when current, otherwise computed on the spot.
    var lemmatizedSteps: [RecipeStep] {
        let keys = ingredientKeys
        if stepsSourceHash == StepLemmatizer.sourceHash(instructions: instructions, ingredientKeys: keys),
           let stored = try? JSONDecoder().decode([RecipeStep].self, from: stepsJSON) {
            return stored
        }
        return StepLemmatizer.steps(from: instructions, ingredientKeys: keys)
    }
}

// MARK: - Keeping stored lemmas current

/// Fills in lemmatised ingredient names and recipe steps before anything is stored, so
/// matching never has to lemmatise on the fly. Hooks every save of a container's main
/// context, and backfills rows written before these fields existed.
@MainActor
enum LemmaIndexer {
    private static var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static func install(on container: ModelContainer) {
        let context = container.mainContext
        guard observers[ObjectIdentifier(context)] == nil else { return }
        observers[ObjectIdentifier(context)] = NotificationCenter.default.addObserver(forName: ModelContext.willSave, object: context, queue: nil) { _ in
            MainActor.assumeIsolated { refreshPending(in: context) }
        }
    }

    /// Updates every inserted or changed row in `context`. Only writes values that differ,
    /// so it never dirties an otherwise-clean object.
    static func refreshPending(in context: ModelContext) {
        let touched = context.insertedModelsArray + context.changedModelsArray
        var recipes: [PersistentIdentifier: Recipe] = [:]
        for model in touched {
            switch model {
            case let item as Ingredient:
                refresh(item)
            case let item as RecipeIngredient:
                refresh(item)
                if let recipe = item.recipe { recipes[recipe.persistentModelID] = recipe }
            case let recipe as Recipe:
                recipes[recipe.persistentModelID] = recipe
            default:
                continue
            }
        }
        recipes.values.forEach(refresh)
    }

    /// Rows synced from older app versions, created before these fields existed, or stored
    /// with a key from an older matcher. Every key is recomputed; `refresh` only writes the
    /// ones that changed.
    static func backfill(_ context: ModelContext) {
        let ingredients = (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []
        ingredients.forEach(refresh)
        let recipeIngredients = (try? context.fetch(FetchDescriptor<RecipeIngredient>())) ?? []
        recipeIngredients.forEach(refresh)
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        recipes.forEach(refresh)
        if context.hasChanges { try? context.save() }
    }

    static func refresh(_ item: Ingredient) {
        let lemma = IngredientNameMatcher.key(item.name)
        if item.lemmaName != lemma { item.lemmaName = lemma }
    }

    static func refresh(_ item: RecipeIngredient) {
        let lemma = IngredientNameMatcher.key(item.name)
        if item.lemmaName != lemma { item.lemmaName = lemma }
    }

    static func refresh(_ recipe: Recipe) {
        let keys = recipe.ingredients.map { IngredientNameMatcher.key($0.name) }.filter { !$0.isEmpty }
        let hash = StepLemmatizer.sourceHash(instructions: recipe.instructions, ingredientKeys: keys)
        guard recipe.stepsSourceHash != hash else { return }
        let steps = StepLemmatizer.steps(from: recipe.instructions, ingredientKeys: keys)
        recipe.stepsJSON = (try? JSONEncoder().encode(steps)) ?? Data()
        recipe.stepsSourceHash = hash
    }
}

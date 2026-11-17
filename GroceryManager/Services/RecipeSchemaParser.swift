import Foundation

/// A recipe as found on a web page or in an export file, before it is turned into a draft.
struct ParsedRecipe: Equatable {
    var name: String
    var ingredientLines: [String]
    var instructions: [String]
    var servings: Int?
    var imageURL: String = ""
    var sourceURL: String = ""
    var prepMinutes: Int = 0
    var cookMinutes: Int = 0
    var nutritionPerServing: NutritionFacts?
    var tags: [String] = []
}

/// Reads the standard schema.org `Recipe` markup that nearly every recipe site publishes
/// (JSON-LD first, microdata as a fallback). No model, no network: pure parsing.
enum RecipeSchemaParser {
    static func parse(html: String, sourceURL: URL? = nil) -> ParsedRecipe? {
        for json in jsonLDBlocks(in: html) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { continue }
            if let recipeObject = findRecipe(in: object), var recipe = parse(schemaObject: recipeObject) {
                if recipe.sourceURL.isEmpty { recipe.sourceURL = sourceURL?.absoluteString ?? "" }
                return recipe
            }
        }
        if var recipe = parseMicrodata(html: html) {
            recipe.sourceURL = sourceURL?.absoluteString ?? ""
            return recipe
        }
        return nil
    }

    // MARK: JSON-LD

    static func jsonLDBlocks(in html: String) -> [String] {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
                .replacingOccurrences(of: "<!--", with: "")
                .replacingOccurrences(of: "-->", with: "")
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Depth-first search for an object whose `@type` is (or includes) "Recipe".
    static func findRecipe(in object: Any) -> [String: Any]? {
        if let dictionary = object as? [String: Any] {
            if isRecipe(dictionary) { return dictionary }
            for key in ["@graph", "mainEntity", "mainEntityOfPage", "itemListElement"] {
                if let nested = dictionary[key], let found = findRecipe(in: nested) { return found }
            }
            return nil
        }
        if let array = object as? [Any] {
            for element in array {
                if let found = findRecipe(in: element) { return found }
            }
        }
        return nil
    }

    private static func isRecipe(_ dictionary: [String: Any]) -> Bool {
        if let type = dictionary["@type"] as? String { return type.caseInsensitiveCompare("Recipe") == .orderedSame }
        if let types = dictionary["@type"] as? [String] { return types.contains { $0.caseInsensitiveCompare("Recipe") == .orderedSame } }
        return false
    }

    static func parse(schemaObject recipe: [String: Any]) -> ParsedRecipe? {
        guard let name = text(recipe["name"]), !name.isEmpty else { return nil }
        let ingredientLines = stringList(recipe["recipeIngredient"] ?? recipe["ingredients"])
        guard !ingredientLines.isEmpty else { return nil }

        var parsed = ParsedRecipe(
            name: name,
            ingredientLines: ingredientLines,
            instructions: instructionList(recipe["recipeInstructions"]),
            servings: servings(from: recipe["recipeYield"])
        )
        parsed.imageURL = imageURL(recipe["image"])
        parsed.sourceURL = text(recipe["url"]) ?? text((recipe["mainEntityOfPage"] as? [String: Any])?["@id"]) ?? ""
        parsed.prepMinutes = minutes(fromISO8601: text(recipe["prepTime"]))
        parsed.cookMinutes = minutes(fromISO8601: text(recipe["cookTime"]))
        if parsed.prepMinutes == 0, parsed.cookMinutes == 0 {
            parsed.cookMinutes = minutes(fromISO8601: text(recipe["totalTime"]))
        }
        if let nutrition = recipe["nutrition"] as? [String: Any] {
            parsed.nutritionPerServing = nutritionFacts(from: nutrition)
        }
        parsed.tags = (stringList(recipe["recipeCategory"]) + stringList(recipe["recipeCuisine"]) + stringList(recipe["keywords"]))
            .flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty }
            .prefix(8)
            .map { $0 }
        return parsed
    }

    // MARK: Field helpers

    static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let cleaned = HTMLText.stripTags(string)
            return cleaned.isEmpty ? nil : cleaned
        case let number as NSNumber: return number.stringValue
        case let array as [Any]: return array.compactMap(text).first
        case let dictionary as [String: Any]: return text(dictionary["name"]) ?? text(dictionary["text"]) ?? text(dictionary["@value"])
        default: return nil
        }
    }

    static func stringList(_ value: Any?) -> [String] {
        switch value {
        case let string as String:
            return string.components(separatedBy: .newlines).map { HTMLText.stripTags($0) }.filter { !$0.isEmpty }
        case let array as [Any]:
            return array.compactMap { text($0) }
        default:
            return []
        }
    }

    static func instructionList(_ value: Any?) -> [String] {
        switch value {
        case let string as String:
            return splitInstructionText(HTMLText.stripTags(string))
        case let array as [Any]:
            return array.flatMap { element -> [String] in
                if let string = element as? String { return splitInstructionText(HTMLText.stripTags(string)) }
                guard let dictionary = element as? [String: Any] else { return [] }
                if let items = dictionary["itemListElement"] { return instructionList(items) }
                return [text(dictionary["text"]) ?? text(dictionary["name"])].compactMap { $0 }
            }
        case let dictionary as [String: Any]:
            return instructionList(dictionary["itemListElement"] ?? dictionary["text"])
        default:
            return []
        }
    }

    static func splitInstructionText(_ text: String) -> [String] {
        let byLine = text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"^\s*(?:step\s*)?\d+[.):]\s*"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return byLine
    }

    static func servings(from value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String:
            let digits = string.replacingOccurrences(of: #"[^0-9]+"#, with: " ", options: .regularExpression)
            return digits.split(separator: " ").compactMap { Int($0) }.first
        case let array as [Any]: return array.compactMap(servings(from:)).first
        default: return nil
        }
    }

    static func imageURL(_ value: Any?) -> String {
        switch value {
        case let string as String: return string
        case let array as [Any]: return array.compactMap { imageURL($0) }.first { !$0.isEmpty } ?? ""
        case let dictionary as [String: Any]: return imageURL(dictionary["url"] ?? dictionary["contentUrl"])
        default: return ""
        }
    }

    /// "PT1H30M" → 90. Tolerates "PT45M", "P0DT0H20M" and plain minutes.
    static func minutes(fromISO8601 value: String?) -> Int {
        guard let value, !value.isEmpty else { return 0 }
        if let plain = Int(value) { return plain }
        var total = 0
        let pattern = #"(\d+(?:\.\d+)?)\s*([DHMS])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
        let upper = value.uppercased()
        let timePart = upper.split(separator: "T", maxSplits: 1).map(String.init)
        for (index, part) in timePart.enumerated() {
            for match in regex.matches(in: part, range: NSRange(part.startIndex..., in: part)) {
                guard let numberRange = Range(match.range(at: 1), in: part), let unitRange = Range(match.range(at: 2), in: part),
                      let number = Double(part[numberRange]) else { continue }
                switch (part[unitRange], index) {
                case ("D", _): total += Int(number * 1440)
                case ("H", _): total += Int(number * 60)
                case ("M", 1), ("M", 0) where timePart.count == 1: total += Int(number)
                case ("M", 0): break // months, ignore
                default: break
                }
            }
        }
        return total
    }

    static func nutritionFacts(from nutrition: [String: Any]) -> NutritionFacts? {
        func grams(_ key: String) -> Double {
            guard let raw = text(nutrition[key]) else { return 0 }
            return raw.replacingOccurrences(of: ",", with: "").split(separator: " ")
                .compactMap { Double($0.filter { "0123456789.".contains($0) }) }.first ?? 0
        }
        let facts = NutritionFacts(calories: grams("calories"), protein: grams("proteinContent"), carbs: grams("carbohydrateContent"), fat: grams("fatContent"))
        return facts.isEmpty ? nil : facts
    }

    // MARK: Microdata fallback

    static func parseMicrodata(html: String) -> ParsedRecipe? {
        func values(itemprop: String) -> [String] {
            let pattern = #"itemprop\s*=\s*["']\#(itemprop)["'][^>]*>([\s\S]*?)<"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
            return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
                guard let range = Range(match.range(at: 1), in: html) else { return nil }
                let value = HTMLText.stripTags(String(html[range]))
                return value.isEmpty ? nil : value
            }
        }
        let ingredients = values(itemprop: "recipeIngredient") + values(itemprop: "ingredients")
        guard !ingredients.isEmpty, let name = values(itemprop: "name").first else { return nil }
        return ParsedRecipe(
            name: name,
            ingredientLines: ingredients,
            instructions: values(itemprop: "recipeInstructions"),
            servings: values(itemprop: "recipeYield").first.flatMap { servings(from: $0) }
        )
    }
}

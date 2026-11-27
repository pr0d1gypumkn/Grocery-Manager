import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Extracts a recipe from free text with the on-device Apple Intelligence model. On devices
/// without Apple Intelligence (or while its model is still downloading) it falls back to
/// `PlainTextRecipeParser`, so pasted notes, photos and captions import on every device.
final class OnDeviceRecipeImporter {
    /// Whether the Apple Intelligence model can be used right now.
    static var isModelAvailable: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
#endif
        return false
    }

    /// Page text (`.url` sources, or a web page passed as a note by `RecipeWebImporter`) is
    /// mostly menus and comments, so the plain-text fallback only trusts labelled sections there.
    func importRecipe(from source: RecipeImportSource, isPageText: Bool = false) async throws -> ImportedRecipeDraft {
        let sourceText: String
        switch source {
        case .note(let note):
            sourceText = note
        case .url(let url):
            sourceText = HTMLText.plainText(fromDocument: try await HTMLFetcher.fetch(url))
        }

        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeImportError.emptySource
        }

        let requireSections: Bool
        if case .url = source { requireSections = true } else { requireSections = isPageText }

        guard Self.isModelAvailable else {
            return try Self.plainTextDraft(sourceText, requireSections: requireSections)
        }
        do {
            return try await modelDraft(sourceText)
        } catch RecipeImportError.modelAssetsUnavailable {
            return try Self.plainTextDraft(sourceText, requireSections: requireSections)
        }
    }

    private static func plainTextDraft(_ text: String, requireSections: Bool) throws -> ImportedRecipeDraft {
        guard let draft = PlainTextRecipeParser.parse(text, requireSections: requireSections) else {
            throw RecipeImportError.noRecipeContent
        }
        return draft
    }

    private func modelDraft(_ sourceText: String) async throws -> ImportedRecipeDraft {
#if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw RecipeImportError.unsupported
        }

        let session = LanguageModelSession(instructions: """
        You extract recipes from user-provided notes or web page text. Return only the structured recipe data requested by the schema. Preserve the recipe's intended quantities. Use one of these units exactly: item, dozen, g, kg, ml, L, oz, lb, fl oz, tsp, tbsp, cup, pt, qt, gal, pinch, dash, smidgen. Use item when no unit is stated. Do not invent ingredients that are not in the source.
        """)
        let response: LanguageModelSession.Response<GeneratedRecipe>
        do {
            response = try await session.respond(
                to: """
                Parse this recipe source into a recipe name, how many servings it makes, concise numbered instructions, and required ingredients. Normalize quantities to positive numbers when possible.

                SOURCE:
                \(sourceText.prefix(40_000))
                """,
                generating: GeneratedRecipe.self
            )
        } catch {
            // Apple may report a missing model catalog even when availability says available.
            throw RecipeImportError.modelAssetsUnavailable
        }

        let generated = response.content
        guard !generated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeImportError.noRecipeContent
        }

        var draft = ImportedRecipeDraft(
            name: generated.name,
            instructions: generated.instructions,
            ingredients: generated.ingredients.map {
                let cleaned = IngredientLineParser.cleanName($0.name)
                return DraftRecipeIngredient(
                    name: cleaned.name,
                    quantity: max($0.quantity, 0),
                    unit: IngredientLineParser.unitAlias($0.unit) ?? QuantityUnit(rawValue: $0.unit)?.rawValue ?? "item",
                    note: cleaned.note
                )
            }
        )
        draft.servings = generated.servings > 0 ? generated.servings : nil
        draft.method = "on-device"
        return draft
#else
        throw RecipeImportError.unsupported
#endif
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct GeneratedRecipe {
        var name: String
        @Guide(description: "How many servings the recipe makes; 0 if unknown")
        var servings: Int
        var instructions: String
        var ingredients: [GeneratedIngredient]
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedIngredient {
        @Guide(description: "Just the ingredient, e.g. \"refried beans\" or \"flour tortillas\": no amounts, sizes, packaging or parentheses")
        var name: String
        var quantity: Double
        var unit: String
    }
#endif
}

/// Reads a recipe out of plain text without a language model: a title, ingredient lines and
/// steps, found by section headings ("Ingredients", "Method", …) or, without headings, by
/// shape (lines that start with an amount are ingredients, longer sentences are steps).
enum PlainTextRecipeParser {
    private static let ingredientHeadings: Set<String> = ["ingredients", "ingredient list", "you will need", "what you need", "you'll need", "shopping list"]
    private static let stepHeadings: Set<String> = ["instructions", "directions", "method", "steps", "preparation", "how to make it", "how to make", "to make"]
    private static let bulletCharacters = CharacterSet(charactersIn: "•·-–—*▢☐□◦‣○●✓✔︎▪️🔸🔹>")

    private enum Section { case none, ingredients, steps }

    static func parse(_ text: String, requireSections: Bool = false) -> ImportedRecipeDraft? {
        var title: String?
        var servings: Int?
        var ingredientLines: [String] = []
        var steps: [String] = []
        var section = Section.none
        var sawIngredientHeading = false

        for rawLine in lines(in: text) {
            let line = stripBullet(rawLine)
            guard !line.isEmpty else { continue }
            let key = headingKey(line)

            if ingredientHeadings.contains(key) || key.hasPrefix("ingredients for") {
                section = .ingredients
                sawIngredientHeading = true
                continue
            }
            if stepHeadings.contains(key) {
                section = .steps
                continue
            }
            if servings == nil, let count = servingsCount(in: line), line.count < 40 {
                servings = count
                continue
            }

            switch section {
            case .ingredients:
                // A long sentence after the list usually means the steps started without a heading.
                if isStepLike(line), !startsWithAmount(line) {
                    section = .steps
                    steps.append(stripStepNumber(line))
                } else if line.count <= 120 {
                    ingredientLines.append(line)
                }
            case .steps:
                steps.append(stripStepNumber(line))
            case .none:
                if requireSections {
                    if title == nil, line.count <= 80 { title = line }
                } else if startsWithAmount(line), line.count <= 80, !isNumberedStep(rawLine) {
                    ingredientLines.append(line)
                } else if isNumberedStep(rawLine) || isStepLike(line) {
                    steps.append(stripStepNumber(line))
                } else if title == nil, line.count <= 80 {
                    title = line
                }
            }
        }

        if requireSections, !sawIngredientHeading { return nil }
        let ingredients = ingredientLines.compactMap(ingredient(from:))
        guard !ingredients.isEmpty || steps.count >= 2 else { return nil }

        let name = title.map(cleanTitle) ?? ""
        var draft = ImportedRecipeDraft(
            name: name.isEmpty ? "Imported recipe" : name,
            instructions: steps.enumerated().map { steps.count > 1 ? "\($0.offset + 1). \($0.element)" : $0.element }.joined(separator: "\n"),
            ingredients: ingredients
        )
        draft.servings = servings
        draft.method = "text"
        return draft
    }

    // MARK: Lines

    private static func lines(in text: String) -> [String] {
        // Captions often run a list together on one line: "… • 2 eggs • 1 cup milk".
        text.replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: " • ", with: "\n• ")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func stripBullet(_ line: String) -> String {
        var value = Substring(line)
        while let first = value.unicodeScalars.first, bulletCharacters.contains(first) {
            value = value.dropFirst()
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static func headingKey(_ line: String) -> String {
        line.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ":：.#*_ ").union(.whitespaces))
    }

    private static func cleanTitle(_ line: String) -> String {
        line.trimmingCharacters(in: CharacterSet(charactersIn: "#*_:").union(.whitespaces))
    }

    // MARK: Classification

    private static func startsWithAmount(_ line: String) -> Bool {
        guard let first = line.unicodeScalars.first else { return false }
        return CharacterSet.decimalDigits.contains(first) || "¼½¾⅓⅔⅛⅜⅝⅞".unicodeScalars.contains(first)
            || line.lowercased().hasPrefix("a pinch") || line.lowercased().hasPrefix("a handful")
    }

    private static func isNumberedStep(_ line: String) -> Bool {
        line.range(of: #"^\s*(step\s*)?\d{1,2}\s*[.):]\s+\S"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isStepLike(_ line: String) -> Bool {
        line.split(separator: " ").count >= 8 && (line.hasSuffix(".") || line.hasSuffix("!") || line.count > 60)
    }

    private static func stripStepNumber(_ line: String) -> String {
        line.replacingOccurrences(of: #"^\s*(step\s*)?\d{1,2}\s*[.):]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private static func servingsCount(in line: String) -> Int? {
        let pattern = #"^(?:serves|servings|makes|yield|yields)\s*[:\-]?\s*(\d{1,2})"#
        guard let range = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return Int(line[range].filter(\.isNumber))
    }

    private static func ingredient(from line: String) -> DraftRecipeIngredient? {
        let parsed = IngredientLineParser.parse(line)
        let name = parsed.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { return nil }
        return DraftRecipeIngredient(name: name, quantity: parsed.quantity, unit: parsed.unit, note: parsed.note)
    }
}

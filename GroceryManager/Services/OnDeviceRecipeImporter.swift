import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Extracts a recipe from free text with the on-device Apple Intelligence model.
final class OnDeviceRecipeImporter {
    func importRecipe(from source: RecipeImportSource) async throws -> ImportedRecipeDraft {
#if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw RecipeImportError.unsupported
        }

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

        guard case .available = SystemLanguageModel.default.availability else {
            throw RecipeImportError.modelUnavailable
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
                DraftRecipeIngredient(
                    name: $0.name,
                    quantity: max($0.quantity, 0),
                    unit: IngredientLineParser.unitAlias($0.unit) ?? QuantityUnit(rawValue: $0.unit)?.rawValue ?? "item"
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
        var name: String
        var quantity: Double
        var unit: String
    }
#endif
}

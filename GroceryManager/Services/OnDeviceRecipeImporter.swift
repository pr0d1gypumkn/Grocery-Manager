import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct ImportedRecipeDraft {
    let name: String
    let instructions: String
    let ingredients: [DraftRecipeIngredient]
}

enum RecipeImportSource {
    case note(String)
    case url(URL)
}

enum RecipeImportError: LocalizedError {
    case unsupported
    case modelUnavailable
    case modelAssetsUnavailable
    case emptySource
    case invalidURL
    case networkFailure(String)
    case noRecipeContent

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "On-device recipe parsing requires iOS 26 or later."
        case .modelUnavailable:
            "Apple Intelligence is unavailable or still preparing on this device. Turn on Apple Intelligence in Settings and try again."
        case .modelAssetsUnavailable:
            "The on-device Apple Intelligence model is not installed or is still downloading. Connect to Wi-Fi and power, finish the model download, then try again."
        case .emptySource:
            "Add a recipe note or URL first."
        case .invalidURL:
            "Enter a complete recipe URL, such as https://example.com/recipe."
        case .networkFailure(let message):
            "The recipe page could not be loaded. \(message)"
        case .noRecipeContent:
            "No recipe content was found at that source."
        }
    }
}

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
            sourceText = try await fetchRecipeText(from: url)
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
                Parse this recipe source into a recipe name, concise instructions, and required ingredients. Normalize quantities to positive numbers when possible.

                SOURCE:
                \(sourceText.prefix(40_000))
                """,
                generating: GeneratedRecipe.self
            )
        } catch {
            // Apple may report a missing model catalog even when availability says available.
            throw RecipeImportError.modelAssetsUnavailable
        }

        let draft = response.content
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeImportError.noRecipeContent
        }

        return ImportedRecipeDraft(
            name: draft.name,
            instructions: draft.instructions,
            ingredients: draft.ingredients.map {
                DraftRecipeIngredient(
                    name: $0.name,
                    quantity: max($0.quantity, 0),
                    unit: normalizedUnit($0.unit)
                )
            }
        )
#else
        throw RecipeImportError.unsupported
#endif
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct GeneratedRecipe {
        var name: String
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

    private func normalizedUnit(_ unit: String) -> String {
        let value = unit
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let aliases: [String: QuantityUnit] = [
            "piece": .item, "pieces": .item, "each": .item,
            "doz": .dozen,
            "gram": .grams, "grams": .grams,
            "kilogram": .kilograms, "kilograms": .kilograms,
            "ounce": .ounces, "ounces": .ounces,
            "pound": .pounds, "pounds": .pounds,
            "milliliter": .milliliters, "milliliters": .milliliters,
            "millilitre": .milliliters, "millilitres": .milliliters,
            "liter": .liters, "liters": .liters, "litre": .liters, "litres": .liters,
            "fluid ounce": .fluidOunces, "fluid ounces": .fluidOunces,
            "teaspoon": .teaspoons, "teaspoons": .teaspoons,
            "tablespoon": .tablespoons, "tablespoons": .tablespoons,
            "cup": .cups, "cups": .cups,
            "pint": .pints, "pints": .pints,
            "quart": .quarts, "quarts": .quarts,
            "gallon": .gallons, "gallons": .gallons,
            "pinches": .pinches, "dashes": .dashes, "smidgens": .smidgens
        ]
        return (QuantityUnit(rawValue: value) ?? aliases[value])?.rawValue ?? "item"
    }

    private func fetchRecipeText(from url: URL) async throws -> String {
        guard let normalizedURL = normalizedURL(from: url),
              ["http", "https"].contains(normalizedURL.scheme?.lowercased() ?? "") else {
            throw RecipeImportError.invalidURL
        }

        var request = URLRequest(url: normalizedURL)
        request.timeoutInterval = 30
        request.setValue("text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RecipeImportError.networkFailure("The server returned an unsupported response.")
            }
            guard (200..<400).contains(httpResponse.statusCode) else {
                throw RecipeImportError.networkFailure("The server returned HTTP \(httpResponse.statusCode).")
            }

            let encoding = httpResponse.textEncodingName.flatMap { String.Encoding(ianaName: $0) } ?? .utf8
            guard let html = String(data: data, encoding: encoding) ?? String(data: data, encoding: .utf8) else {
                throw RecipeImportError.networkFailure("The page was not readable as text.")
            }

            return html
                .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } catch let error as RecipeImportError {
            throw error
        } catch {
            throw RecipeImportError.networkFailure(error.localizedDescription)
        }
    }

    private func normalizedURL(from url: URL) -> URL? {
        var value = url.absoluteString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))

        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "https://\(value)"
        }

        return URL(string: value.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? value)
    }
}

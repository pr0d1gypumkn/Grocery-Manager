import Foundation

struct ImportedRecipeDraft {
    var name: String
    var instructions: String
    var ingredients: [DraftRecipeIngredient]
    var servings: Int? = nil
    var sourceURL: String = ""
    var imageURL: String = ""
    var prepMinutes: Int = 0
    var cookMinutes: Int = 0
    var nutritionPerServing: NutritionFacts? = nil
    var tags: [String] = []
    /// "schema", "on-device", "paprika", "json"
    var method: String = ""

    init(name: String, instructions: String, ingredients: [DraftRecipeIngredient]) {
        self.name = name
        self.instructions = instructions
        self.ingredients = ingredients
    }

    init(parsed: ParsedRecipe, method: String) {
        name = parsed.name
        instructions = parsed.instructions.enumerated().map { index, step in
            parsed.instructions.count > 1 ? "\(index + 1). \(step)" : step
        }.joined(separator: "\n")
        ingredients = parsed.ingredientLines.map { line in
            let parsedLine = IngredientLineParser.parse(line)
            return DraftRecipeIngredient(name: parsedLine.name, quantity: parsedLine.quantity, unit: parsedLine.unit, note: parsedLine.note)
        }
        servings = parsed.servings
        sourceURL = parsed.sourceURL
        imageURL = parsed.imageURL
        prepMinutes = parsed.prepMinutes
        cookMinutes = parsed.cookMinutes
        nutritionPerServing = parsed.nutritionPerServing
        tags = parsed.tags
        self.method = method
    }
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

/// Downloads a page as HTML text.
enum HTMLFetcher {
    static func fetch(_ url: URL) async throws -> String {
        guard let normalizedURL = normalized(url), ["http", "https"].contains(normalizedURL.scheme?.lowercased() ?? "") else {
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
        } catch let error as RecipeImportError {
            throw error
        } catch {
            throw RecipeImportError.networkFailure(error.localizedDescription)
        }
    }

    static func normalized(_ url: URL) -> URL? {
        var value = url.absoluteString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "https://\(value)"
        }
        return URL(string: value.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? value)
    }
}

/// Imports a recipe from a URL: the page's schema.org markup first (fast, exact, works on
/// every device), with the on-device language model as the fallback for pages without it.
struct RecipeWebImporter {
    var fallback: (String) async throws -> ImportedRecipeDraft = { text in
        try await OnDeviceRecipeImporter().importRecipe(from: .note(text), isPageText: true)
    }

    func importRecipe(from url: URL) async throws -> ImportedRecipeDraft {
        let html = try await HTMLFetcher.fetch(url)
        if let parsed = RecipeSchemaParser.parse(html: html, sourceURL: url) {
            return ImportedRecipeDraft(parsed: parsed, method: "schema")
        }
        let text = HTMLText.plainText(fromDocument: html)
        guard !text.isEmpty else { throw RecipeImportError.noRecipeContent }
        var draft = try await fallback(text)
        draft.sourceURL = url.absoluteString
        draft.method = "on-device"
        return draft
    }
}

extension String.Encoding {
    init?(ianaName: String) {
        let encoding = CFStringConvertIANACharSetNameToEncoding(ianaName as CFString)
        guard encoding != kCFStringEncodingInvalidId else { return nil }
        self.init(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}

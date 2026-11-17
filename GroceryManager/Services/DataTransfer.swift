import Compression
import Foundation
import SwiftData

// MARK: - Export format (version 1)

/// Everything the user owns, in a plain JSON shape that other apps can read. Nothing in it
/// depends on SwiftData identifiers, so it round-trips between devices and the web app.
struct ExportBundle: Codable {
    struct Location: Codable { var name: String; var icon: String }
    struct PantryItem: Codable {
        var name: String; var quantity: Double; var unit: String; var initialQuantity: Double
        var reorderThreshold: Double; var category: String; var expiryDate: Date; var location: String?
    }
    struct RecipeIngredientExport: Codable { var name: String; var quantity: Double; var unit: String; var note: String }
    struct RecipeExport: Codable {
        var name: String; var instructions: String; var servings: Int; var sourceURL: String; var imageURL: String
        var prepMinutes: Int; var cookMinutes: Int; var tags: [String]; var nutritionPerServing: NutritionFacts?
        var ingredients: [RecipeIngredientExport]
    }
    struct Meal: Codable { var date: Date; var mealType: String; var recipe: String; var servings: Int; var note: String; var isCooked: Bool }
    struct Grocery: Codable {
        var name: String; var quantity: Double; var unit: String; var category: String; var isChecked: Bool
        var source: String; var note: String; var priceCents: Int; var currencyCode: String
    }
    struct Member: Codable { var name: String; var portionMultiplier: Double; var dietTags: String }
    struct HouseholdExport: Codable { var name: String; var members: [Member] }
    struct Preferences: Codable { var region: String; var unitSystem: String; var weeklyBudgetCents: Int; var dietTags: [String] }

    var version = 1
    var app = "mealy"
    var exportedAt = Date.now
    var locations: [Location] = []
    var pantry: [PantryItem] = []
    var recipes: [RecipeExport] = []
    var mealPlan: [Meal] = []
    var groceries: [Grocery] = []
    var household: HouseholdExport?
    var preferences: Preferences?
}

struct ImportSummary: Equatable {
    var recipes = 0
    var pantryItems = 0
    var meals = 0
    var groceries = 0
    var locations = 0

    var total: Int { recipes + pantryItems + meals + groceries + locations }

    var description: String {
        var parts: [String] = []
        if recipes > 0 { parts.append("\(recipes) recipe\(recipes == 1 ? "" : "s")") }
        if pantryItems > 0 { parts.append("\(pantryItems) stock item\(pantryItems == 1 ? "" : "s")") }
        if meals > 0 { parts.append("\(meals) planned meal\(meals == 1 ? "" : "s")") }
        if groceries > 0 { parts.append("\(groceries) grocery line\(groceries == 1 ? "" : "s")") }
        if locations > 0 { parts.append("\(locations) location\(locations == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing new to import." : "Imported " + parts.formatted(.list(type: .and)) + "."
    }
}

enum DataTransferError: LocalizedError {
    case unreadable
    case unknownFormat
    case emptyArchive

    var errorDescription: String? {
        switch self {
        case .unreadable: "The file could not be read."
        case .unknownFormat: "This file isn't a Mealy export, a recipe JSON file, a Paprika export or a CSV list."
        case .emptyArchive: "The archive contains no recipes."
        }
    }
}

// MARK: - Export

@MainActor
struct DataExporter {
    let modelContext: ModelContext

    func bundle(preferences: ExportBundle.Preferences?) -> ExportBundle {
        var bundle = ExportBundle()
        bundle.preferences = preferences
        bundle.locations = fetch(StorageLocation.self).map { .init(name: $0.name, icon: $0.icon) }
        bundle.pantry = fetch(Ingredient.self).filter { !$0.isPreparedMeal }.map {
            .init(name: $0.name, quantity: $0.quantity, unit: $0.unit, initialQuantity: $0.initialQuantity,
                  reorderThreshold: $0.reorderThreshold, category: $0.category, expiryDate: $0.expiryDate, location: $0.location?.name)
        }
        bundle.recipes = fetch(Recipe.self).map(Self.export)
        bundle.mealPlan = fetch(MealPlanEntry.self).compactMap { entry in
            guard let recipe = entry.recipe else { return nil }
            return .init(date: entry.date, mealType: entry.mealTypeRaw, recipe: recipe.name, servings: entry.servings, note: entry.note, isCooked: entry.isCooked)
        }
        bundle.groceries = fetch(GroceryItem.self).map {
            .init(name: $0.name, quantity: $0.quantity, unit: $0.unit, category: $0.category, isChecked: $0.isChecked,
                  source: $0.source, note: $0.note, priceCents: $0.priceCents, currencyCode: $0.currencyCode)
        }
        if let household = fetch(Household.self).first {
            bundle.household = .init(
                name: household.name,
                members: household.members.sorted { $0.sortOrder < $1.sortOrder }.map { .init(name: $0.name, portionMultiplier: $0.portionMultiplier, dietTags: $0.dietTags) }
            )
        }
        return bundle
    }

    static func export(_ recipe: Recipe) -> ExportBundle.RecipeExport {
        .init(
            name: recipe.name, instructions: recipe.instructions, servings: recipe.servings, sourceURL: recipe.sourceURL,
            imageURL: recipe.imageURL, prepMinutes: recipe.prepMinutes, cookMinutes: recipe.cookMinutes, tags: recipe.tagList,
            nutritionPerServing: recipe.declaredNutrition,
            ingredients: recipe.orderedIngredients.map { .init(name: $0.name, quantity: $0.requiredQuantity, unit: $0.unit, note: $0.note) }
        )
    }

    func json(preferences: ExportBundle.Preferences?) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle(preferences: preferences))
    }

    func groceriesCSV() -> String {
        CSV.write(
            header: ["name", "quantity", "unit", "category", "checked", "note", "price", "currency"],
            rows: fetch(GroceryItem.self).map { [$0.name, $0.quantity.quantityText, $0.unit, $0.category, $0.isChecked ? "yes" : "no", $0.note,
                                                 $0.priceCents > 0 ? String(format: "%.2f", Double($0.priceCents) / 100) : "", $0.currencyCode] }
        )
    }

    func pantryCSV() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return CSV.write(
            header: ["name", "quantity", "unit", "category", "expiry", "location"],
            rows: fetch(Ingredient.self).filter { !$0.isPreparedMeal }.map {
                [$0.name, $0.quantity.quantityText, $0.unit, $0.category, formatter.string(from: $0.expiryDate), $0.location?.name ?? ""]
            }
        )
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }
}

// MARK: - Import

@MainActor
struct DataImporter {
    let modelContext: ModelContext

    /// Detects the format from the bytes and file name, then imports.
    func importFile(data: Data, fileName: String) throws -> ImportSummary {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "paprikarecipes" || ZipArchive.isZip(data) {
            return try importPaprikaArchive(data)
        }
        if ext == "csv" || (ext.isEmpty && looksLikeCSV(data)) {
            return try importCSV(String(decoding: data, as: UTF8.self))
        }
        if let json = try? JSONSerialization.jsonObject(with: data) {
            return try importJSON(json)
        }
        if ext == "paprikarecipe", let inflated = Gzip.decompress(data), let json = try? JSONSerialization.jsonObject(with: inflated) {
            return try importJSON(json)
        }
        throw DataTransferError.unknownFormat
    }

    // MARK: JSON

    func importJSON(_ object: Any) throws -> ImportSummary {
        if let dictionary = object as? [String: Any] {
            if dictionary["app"] as? String == "mealy" || (dictionary["version"] != nil && dictionary["recipes"] != nil) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let data = try JSONSerialization.data(withJSONObject: dictionary)
                return importBundle(try decoder.decode(ExportBundle.self, from: data))
            }
            if let recipe = parseRecipeObject(dictionary) {
                return ImportSummary(recipes: upsert(recipes: [recipe]))
            }
            throw DataTransferError.unknownFormat
        }
        if let array = object as? [Any] {
            let recipes = array.compactMap { $0 as? [String: Any] }.compactMap(parseRecipeObject)
            guard !recipes.isEmpty else { throw DataTransferError.unknownFormat }
            return ImportSummary(recipes: upsert(recipes: recipes))
        }
        throw DataTransferError.unknownFormat
    }

    /// Accepts schema.org Recipe objects, Paprika recipe objects and our own export shape.
    func parseRecipeObject(_ object: [String: Any]) -> ParsedRecipe? {
        if RecipeSchemaParser.findRecipe(in: object) != nil, let recipe = RecipeSchemaParser.findRecipe(in: object) {
            return RecipeSchemaParser.parse(schemaObject: recipe)
        }
        if let name = object["name"] as? String, let ingredients = object["ingredients"] as? String {
            // Paprika
            var recipe = ParsedRecipe(
                name: name,
                ingredientLines: ingredients.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                instructions: RecipeSchemaParser.splitInstructionText(object["directions"] as? String ?? ""),
                servings: RecipeSchemaParser.servings(from: object["servings"])
            )
            recipe.sourceURL = object["source_url"] as? String ?? ""
            recipe.imageURL = object["image_url"] as? String ?? ""
            recipe.prepMinutes = Self.looseMinutes(object["prep_time"] as? String)
            recipe.cookMinutes = Self.looseMinutes(object["cook_time"] as? String)
            recipe.tags = (object["categories"] as? [String]) ?? []
            if let info = object["nutritional_info"] as? String { recipe.nutritionPerServing = Self.looseNutrition(info) }
            return recipe
        }
        if let name = object["name"] as? String, let ingredients = object["ingredients"] as? [[String: Any]] {
            // Our export shape (or similar)
            let lines = ingredients.compactMap { ingredient -> String? in
                guard let ingredientName = ingredient["name"] as? String else { return nil }
                let quantity = (ingredient["quantity"] as? NSNumber)?.doubleValue ?? 1
                let unit = ingredient["unit"] as? String ?? "item"
                let note = ingredient["note"] as? String ?? ""
                return "\(quantity.quantityText) \(unit) \(ingredientName)\(note.isEmpty ? "" : ", \(note)")"
            }
            var recipe = ParsedRecipe(
                name: name,
                ingredientLines: lines,
                instructions: RecipeSchemaParser.splitInstructionText(object["instructions"] as? String ?? ""),
                servings: (object["servings"] as? NSNumber)?.intValue
            )
            recipe.sourceURL = object["sourceURL"] as? String ?? ""
            recipe.tags = object["tags"] as? [String] ?? []
            return recipe
        }
        return nil
    }

    /// "1 hr 20 min", "45 minutes", "20" → minutes
    static func looseMinutes(_ text: String?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        let lower = text.lowercased()
        let pattern = #"(\d+)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        var total = 0
        for match in regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            guard let numberRange = Range(match.range(at: 1), in: lower), let value = Int(lower[numberRange]) else { continue }
            let unit = Range(match.range(at: 2), in: lower).map { String(lower[$0]) } ?? "m"
            total += unit.hasPrefix("h") ? value * 60 : value
        }
        return total
    }

    /// "Calories: 420, Protein: 30g, ..." → facts
    static func looseNutrition(_ text: String) -> NutritionFacts? {
        func value(_ labels: [String]) -> Double {
            for label in labels {
                let pattern = label + #"[^0-9]{0,6}(\d+(?:\.\d+)?)"#
                if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    let digits = text[range].replacingOccurrences(of: #"[^0-9.]"#, with: "", options: .regularExpression)
                    return Double(digits) ?? 0
                }
            }
            return 0
        }
        let facts = NutritionFacts(calories: value(["calories", "kcal", "energy"]), protein: value(["protein"]), carbs: value(["carb"]), fat: value(["fat"]))
        return facts.isEmpty ? nil : facts
    }

    // MARK: Paprika

    func importPaprikaArchive(_ data: Data) throws -> ImportSummary {
        let entries = try ZipArchive.entries(in: data)
        var recipes: [ParsedRecipe] = []
        for entry in entries {
            let payload = Gzip.decompress(entry.data) ?? entry.data
            guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let recipe = parseRecipeObject(object) else { continue }
            recipes.append(recipe)
        }
        guard !recipes.isEmpty else { throw DataTransferError.emptyArchive }
        return ImportSummary(recipes: upsert(recipes: recipes))
    }

    // MARK: CSV

    func looksLikeCSV(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(200), encoding: .utf8)?.lowercased() else { return false }
        return head.hasPrefix("name,")
    }

    func importCSV(_ text: String) throws -> ImportSummary {
        let rows = CSV.parse(text)
        guard let header = rows.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) else { throw DataTransferError.unknownFormat }
        func column(_ name: String, in row: [String]) -> String? {
            guard let index = header.firstIndex(of: name), index < row.count else { return nil }
            return row[index].trimmingCharacters(in: .whitespaces)
        }
        guard header.contains("name") else { throw DataTransferError.unknownFormat }
        let isPantry = header.contains("expiry") || header.contains("location")
        var summary = ImportSummary()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let locations = fetch(StorageLocation.self)
        let inventory = fetch(Ingredient.self)

        for row in rows.dropFirst() {
            guard let name = column("name", in: row), !name.isEmpty else { continue }
            let quantity = Double(column("quantity", in: row) ?? "") ?? 1
            let unit = IngredientLineParser.unitAlias(column("unit", in: row) ?? "") ?? QuantityUnit(rawValue: column("unit", in: row) ?? "")?.rawValue ?? "item"
            let category = column("category", in: row).flatMap { $0.isEmpty ? nil : $0 } ?? AisleClassifier.category(for: name)
            if isPantry {
                let expiry = column("expiry", in: row).flatMap { formatter.date(from: $0) } ?? ShelfLife.defaultExpiry(for: category)
                let locationName = column("location", in: row) ?? ""
                let location = locations.first { $0.name.caseInsensitiveCompare(locationName) == .orderedSame }
                InventoryViewModel(modelContext: modelContext).restock(name: name, quantity: quantity, unit: unit, category: category, expiryDate: expiry, location: location, existingInventory: inventory)
                summary.pantryItems += 1
            } else {
                let checked = ["yes", "true", "1", "y"].contains((column("checked", in: row) ?? "").lowercased())
                let item = GroceryItem(name: name, quantity: quantity, unit: unit, category: category)
                item.isChecked = checked
                item.note = column("note", in: row) ?? ""
                modelContext.insert(item)
                summary.groceries += 1
            }
        }
        try modelContext.save()
        return summary
    }

    // MARK: Bundle

    func importBundle(_ bundle: ExportBundle) -> ImportSummary {
        var summary = ImportSummary()
        var locations = fetch(StorageLocation.self)
        for location in bundle.locations where !locations.contains(where: { $0.name.caseInsensitiveCompare(location.name) == .orderedSame }) {
            let model = StorageLocation(name: location.name, icon: location.icon)
            modelContext.insert(model)
            locations.append(model)
            summary.locations += 1
        }

        summary.recipes = upsert(recipes: bundle.recipes.map(Self.parsed))
        let recipes = fetch(Recipe.self)

        let inventory = fetch(Ingredient.self)
        for item in bundle.pantry {
            let location = locations.first { $0.name == item.location }
            if let existing = inventory.first(where: { IngredientNameMatcher.matches($0.name, item.name) && $0.location == location }) {
                existing.quantity = item.quantity
                existing.unit = item.unit
                existing.expiryDate = item.expiryDate
                existing.category = item.category
            } else {
                modelContext.insert(Ingredient(name: item.name, quantity: item.quantity, unit: item.unit, initialQuantity: item.initialQuantity,
                                               reorderThreshold: item.reorderThreshold, category: item.category, expiryDate: item.expiryDate, location: location))
            }
            summary.pantryItems += 1
        }

        let existingMeals = fetch(MealPlanEntry.self)
        for meal in bundle.mealPlan {
            guard let recipe = recipes.first(where: { $0.name == meal.recipe }) else { continue }
            let day = Calendar.current.startOfDay(for: meal.date)
            guard !existingMeals.contains(where: { $0.date == day && $0.mealTypeRaw == meal.mealType && $0.recipe === recipe }) else { continue }
            let entry = MealPlanEntry(date: day, mealType: MealType(rawValue: meal.mealType) ?? .dinner, recipe: recipe, servings: meal.servings, note: meal.note)
            entry.isCooked = meal.isCooked
            modelContext.insert(entry)
            summary.meals += 1
        }

        let existingGroceries = fetch(GroceryItem.self)
        for grocery in bundle.groceries where !existingGroceries.contains(where: { IngredientNameMatcher.matches($0.name, grocery.name) }) {
            let item = GroceryItem(name: grocery.name, quantity: grocery.quantity, unit: grocery.unit, category: grocery.category, source: grocery.source)
            item.isChecked = grocery.isChecked
            item.note = grocery.note
            item.priceCents = grocery.priceCents
            item.currencyCode = grocery.currencyCode
            modelContext.insert(item)
            summary.groceries += 1
        }

        if let household = bundle.household, fetch(Household.self).isEmpty {
            let model = Household(name: household.name)
            modelContext.insert(model)
            for (index, member) in household.members.enumerated() {
                let memberModel = HouseholdMember(name: member.name, portionMultiplier: member.portionMultiplier, dietTags: member.dietTags, sortOrder: index)
                memberModel.household = model
                modelContext.insert(memberModel)
            }
        }

        try? modelContext.save()
        return summary
    }

    static func parsed(_ recipe: ExportBundle.RecipeExport) -> ParsedRecipe {
        var parsed = ParsedRecipe(
            name: recipe.name,
            ingredientLines: recipe.ingredients.map { "\($0.quantity.quantityText) \($0.unit) \($0.name)\($0.note.isEmpty ? "" : ", \($0.note)")" },
            instructions: RecipeSchemaParser.splitInstructionText(recipe.instructions),
            servings: recipe.servings
        )
        parsed.sourceURL = recipe.sourceURL
        parsed.imageURL = recipe.imageURL
        parsed.prepMinutes = recipe.prepMinutes
        parsed.cookMinutes = recipe.cookMinutes
        parsed.tags = recipe.tags
        parsed.nutritionPerServing = recipe.nutritionPerServing
        return parsed
    }

    /// Creates or updates recipes by name. Returns how many were written.
    @discardableResult
    func upsert(recipes: [ParsedRecipe]) -> Int {
        let viewModel = RecipeViewModel(modelContext: modelContext)
        let existing = fetch(Recipe.self)
        var count = 0
        for parsed in recipes {
            let draft = ImportedRecipeDraft(parsed: parsed, method: "import")
            let match = existing.first { $0.name.caseInsensitiveCompare(parsed.name) == .orderedSame }
            viewModel.save(draft: draft, existing: match)
            count += 1
        }
        return count
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }
}

// MARK: - CSV

enum CSV {
    static func write(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { row in row.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func next() -> Character? {
            if let pending { defer { } ; let value = pending; return value }
            return iterator.next()
        }

        while true {
            let character: Character?
            if let queued = pending { character = queued; pending = nil } else { character = iterator.next() }
            guard let character else { break }
            if inQuotes {
                if character == "\"" {
                    let lookahead = iterator.next()
                    if lookahead == "\"" { field.append("\"") } else { inQuotes = false; pending = lookahead }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r":
                    if character == "\r" { let lookahead = iterator.next(); if lookahead != "\n" { pending = lookahead } }
                    row.append(field); field = ""
                    if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                    row = []
                default: field.append(character)
                }
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        _ = next
        return rows
    }
}

// MARK: - Zip / gzip (enough for Paprika exports)

struct ZipEntry {
    var name: String
    var data: Data
}

enum ZipArchive {
    static func isZip(_ data: Data) -> Bool {
        data.count > 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4B
    }

    /// Reads entries through the central directory and inflates deflate-compressed ones.
    static func entries(in data: Data) throws -> [ZipEntry] {
        let bytes = [UInt8](data)
        guard bytes.count > 22 else { throw DataTransferError.unreadable }
        // End of central directory record: scan backwards for its signature.
        var eocd: Int?
        var index = bytes.count - 22
        while index >= 0 && index >= bytes.count - 22 - 65_535 {
            if bytes[index] == 0x50, bytes[index + 1] == 0x4B, bytes[index + 2] == 0x05, bytes[index + 3] == 0x06 { eocd = index; break }
            index -= 1
        }
        guard let eocd else { throw DataTransferError.unreadable }
        let entryCount = Int(u16(bytes, eocd + 10))
        var offset = Int(u32(bytes, eocd + 16))
        var entries: [ZipEntry] = []

        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count, u32(bytes, offset) == 0x0201_4B50 else { break }
            let method = u16(bytes, offset + 10)
            let compressedSize = Int(u32(bytes, offset + 20))
            let uncompressedSize = Int(u32(bytes, offset + 24))
            let nameLength = Int(u16(bytes, offset + 28))
            let extraLength = Int(u16(bytes, offset + 30))
            let commentLength = Int(u16(bytes, offset + 32))
            let localOffset = Int(u32(bytes, offset + 42))
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength

            guard localOffset + 30 <= bytes.count, u32(bytes, localOffset) == 0x0403_4B50 else { continue }
            let localNameLength = Int(u16(bytes, localOffset + 26))
            let localExtraLength = Int(u16(bytes, localOffset + 28))
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            guard dataStart + compressedSize <= bytes.count else { continue }
            let payload = Data(bytes[dataStart..<(dataStart + compressedSize)])
            switch method {
            case 0: entries.append(ZipEntry(name: name, data: payload))
            case 8:
                if let inflated = Inflate.raw(payload, expectedSize: uncompressedSize) { entries.append(ZipEntry(name: name, data: inflated)) }
            default: continue
            }
        }
        return entries
    }

    private static func u16(_ bytes: [UInt8], _ at: Int) -> UInt16 { UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8 }
    private static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}

enum Gzip {
    static func decompress(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 { // FEXTRA
            let length = Int(bytes[index]) | Int(bytes[index + 1]) << 8
            index += 2 + length
        }
        if flags & 0x08 != 0 { while index < bytes.count && bytes[index] != 0 { index += 1 }; index += 1 } // FNAME
        if flags & 0x10 != 0 { while index < bytes.count && bytes[index] != 0 { index += 1 }; index += 1 } // FCOMMENT
        if flags & 0x02 != 0 { index += 2 } // FHCRC
        guard index < bytes.count - 8 else { return nil }
        let size = Int(bytes[bytes.count - 4]) | Int(bytes[bytes.count - 3]) << 8 | Int(bytes[bytes.count - 2]) << 16 | Int(bytes[bytes.count - 1]) << 24
        return Inflate.raw(Data(bytes[index..<(bytes.count - 8)]), expectedSize: size)
    }
}

enum Inflate {
    /// Raw DEFLATE (no zlib/gzip header) → bytes.
    static func raw(_ data: Data, expectedSize: Int) -> Data? {
        var output = Data()
        let bufferSize = max(expectedSize, 64 * 1024)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        return data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Data? in
            guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var stream = compression_stream(dst_ptr: destination, dst_size: bufferSize, src_ptr: sourceBase, src_size: source.count, state: nil)
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
            defer { compression_stream_destroy(&stream) }
            stream.src_ptr = sourceBase
            stream.src_size = source.count
            while true {
                stream.dst_ptr = destination
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                if produced > 0 { output.append(destination, count: produced) }
                switch status {
                case COMPRESSION_STATUS_OK: continue
                case COMPRESSION_STATUS_END: return output
                default: return nil
                }
            }
        }
    }
}

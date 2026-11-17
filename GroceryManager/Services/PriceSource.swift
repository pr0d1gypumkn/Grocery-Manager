import Foundation

/// One estimated price for a grocery line.
struct PriceQuote: Codable, Equatable {
    var name: String
    var priceCents: Int
    var currency: String
    var store: String
    var isSale: Bool
    var label: String
}

struct PricedList: Equatable {
    var quotes: [PriceQuote]
    var currency: String
    var totalCents: Int { quotes.reduce(0) { $0 + $1.priceCents } }
    var quotedCount: Int { quotes.count }

    func quote(for name: String) -> PriceQuote? {
        quotes.first { IngredientNameMatcher.matches($0.name, name) }
    }
}

/// Where prices come from. The server aggregates flyers and retailer APIs per region; the
/// on-device mock keeps the feature demoable offline and before any partnership exists.
protocol PriceSource: Sendable {
    var name: String { get }
    func quotes(for lines: [PlannedGroceryLine], region: Region) async throws -> PricedList
}

struct ServerPriceSource: PriceSource {
    let name = "Mealy server"

    private struct Request: Encodable {
        struct Line: Encodable { var name: String; var quantity: Double; var unit: String }
        var region: String
        var lines: [Line]
    }

    private struct Response: Decodable {
        struct Line: Decodable { var name: String; var priceCents: Int?; var currency: String; var store: String?; var isSale: Bool; var label: String? }
        var currency: String
        var lines: [Line]
    }

    func quotes(for lines: [PlannedGroceryLine], region: Region) async throws -> PricedList {
        let request = Request(region: region.rawValue, lines: lines.map { .init(name: $0.name, quantity: $0.quantity, unit: $0.unit) })
        let response = try await APIClient.shared.post("/api/prices/quote", body: request, as: Response.self)
        return PricedList(
            quotes: response.lines.compactMap { line in
                guard let cents = line.priceCents else { return nil }
                return PriceQuote(name: line.name, priceCents: cents, currency: line.currency, store: line.store ?? "", isSale: line.isSale, label: line.label ?? line.name)
            },
            currency: response.currency
        )
    }
}

/// Representative prices so budgets and totals work without any key. Same table as the
/// server mock, so iOS and web agree.
struct MockPriceSource: PriceSource {
    let name = "Demo prices"

    private struct Entry { var per: String; var cents: Double; var label: String }

    private static let table: [String: Entry] = [
        "chicken thigh": Entry(per: "g", cents: 0.66, label: "Chicken thighs"), "chicken breast": Entry(per: "g", cents: 0.88, label: "Chicken breast"),
        "ground beef": Entry(per: "g", cents: 1.2, label: "Ground beef"), "salmon": Entry(per: "item", cents: 699, label: "Salmon fillet"),
        "salmon fillet": Entry(per: "item", cents: 699, label: "Salmon fillet"), "egg": Entry(per: "item", cents: 32, label: "Large eggs"),
        "milk": Entry(per: "ml", cents: 0.11, label: "Whole milk"), "greek yogurt": Entry(per: "g", cents: 0.8, label: "Greek yogurt"),
        "cheddar cheese": Entry(per: "g", cents: 1.1, label: "Cheddar"), "parmesan": Entry(per: "g", cents: 2.2, label: "Parmesan"),
        "butter": Entry(per: "g", cents: 1.0, label: "Butter"), "brown rice": Entry(per: "g", cents: 0.3, label: "Brown rice"),
        "rice": Entry(per: "g", cents: 0.25, label: "Rice"), "quinoa": Entry(per: "g", cents: 0.7, label: "Quinoa"),
        "pasta": Entry(per: "g", cents: 0.3, label: "Pasta"), "rolled oat": Entry(per: "g", cents: 0.3, label: "Rolled oats"),
        "tortilla": Entry(per: "item", cents: 45, label: "Tortillas"), "bread": Entry(per: "item", cents: 349, label: "Bread"),
        "onion": Entry(per: "item", cents: 89, label: "Onion"), "garlic": Entry(per: "item", cents: 20, label: "Garlic"),
        "carrot": Entry(per: "item", cents: 25, label: "Carrots"), "bell pepper": Entry(per: "item", cents: 129, label: "Bell pepper"),
        "broccoli": Entry(per: "item", cents: 249, label: "Broccoli"), "spinach": Entry(per: "g", cents: 1.5, label: "Spinach"),
        "romaine lettuce": Entry(per: "item", cents: 249, label: "Romaine"), "lemon": Entry(per: "item", cents: 69, label: "Lemon"),
        "lime": Entry(per: "item", cents: 39, label: "Lime"), "cilantro": Entry(per: "item", cents: 99, label: "Cilantro"),
        "basil": Entry(per: "item", cents: 299, label: "Basil"), "ginger": Entry(per: "g", cents: 0.6, label: "Ginger"),
        "green onion": Entry(per: "item", cents: 25, label: "Green onions"), "chickpea": Entry(per: "item", cents: 129, label: "Chickpeas"),
        "black bean": Entry(per: "item", cents: 119, label: "Black beans"), "canned tomato": Entry(per: "item", cents: 149, label: "Canned tomatoes"),
        "coconut milk": Entry(per: "ml", cents: 0.6, label: "Coconut milk"), "olive oil": Entry(per: "ml", cents: 1.6, label: "Olive oil"),
        "soy sauce": Entry(per: "ml", cents: 0.8, label: "Soy sauce"), "curry powder": Entry(per: "ml", cents: 5, label: "Curry powder"),
        "cumin": Entry(per: "ml", cents: 5, label: "Cumin"), "honey": Entry(per: "ml", cents: 1.5, label: "Honey"),
        "blueberry": Entry(per: "g", cents: 1.8, label: "Blueberries"), "chia seed": Entry(per: "ml", cents: 3, label: "Chia seeds"),
        "corn": Entry(per: "g", cents: 0.4, label: "Corn"), "frozen pea": Entry(per: "g", cents: 0.35, label: "Frozen peas"),
        "vegetable broth": Entry(per: "ml", cents: 0.3, label: "Vegetable broth"), "sparkling water": Entry(per: "item", cents: 59, label: "Sparkling water"),
        "paper towel": Entry(per: "item", cents: 899, label: "Paper towels"), "tomato": Entry(per: "item", cents: 79, label: "Tomato"),
        "potato": Entry(per: "item", cents: 60, label: "Potato"), "sweet potato": Entry(per: "item", cents: 110, label: "Sweet potato"),
        "lentil": Entry(per: "g", cents: 0.4, label: "Lentils"), "shrimp": Entry(per: "g", cents: 2.0, label: "Shrimp"),
        "ground turkey": Entry(per: "g", cents: 1.0, label: "Ground turkey"), "cucumber": Entry(per: "item", cents: 129, label: "Cucumber"),
        "banana": Entry(per: "item", cents: 25, label: "Banana"), "apple": Entry(per: "item", cents: 80, label: "Apple"),
        "walnut": Entry(per: "g", cents: 2.5, label: "Walnuts"), "peanut butter": Entry(per: "ml", cents: 1.2, label: "Peanut butter"),
        "rice noodle": Entry(per: "g", cents: 0.6, label: "Rice noodles"), "celery": Entry(per: "item", cents: 40, label: "Celery")
    ]

    private static let sales: [Region: [String: Double]] = [
        .unitedStates: ["chicken thigh": 0.75, "salmon": 0.8, "salmon fillet": 0.8, "broccoli": 0.7],
        .canada: ["ground beef": 0.7, "bell pepper": 0.6, "greek yogurt": 0.8]
    ]

    func quotes(for lines: [PlannedGroceryLine], region: Region) async throws -> PricedList {
        quoteList(for: lines, region: region)
    }

    func quoteList(for lines: [PlannedGroceryLine], region: Region) -> PricedList {
        let currency = region.currencyCode
        let regionFactor = region == .canada ? 1.35 : 1.0
        let quotes = lines.compactMap { line -> PriceQuote? in
            let key = IngredientNameMatcher.key(line.name)
            let tokens = key.split(separator: " ").map(String.init)
            let entry = Self.table[key] ?? Self.table.first { candidate in
                candidate.key.split(separator: " ").allSatisfy { tokens.contains(String($0)) }
            }?.value
            guard let entry else { return nil }
            var amount: Double
            switch entry.per {
            case "item": amount = UnitConverter.convert(line.quantity, from: line.unit, to: "item") ?? 1
            case "g": amount = UnitConverter.convert(line.quantity, from: line.unit, to: "g") ?? UnitConverter.convert(line.quantity, from: line.unit, to: "ml") ?? 1
            default: amount = UnitConverter.convert(line.quantity, from: line.unit, to: "ml") ?? UnitConverter.convert(line.quantity, from: line.unit, to: "g") ?? 1
            }
            if amount <= 0 { amount = 1 }
            let sale = Self.sales[region]?[key] ?? 1
            let cents = max(Int((entry.cents * amount * regionFactor * sale).rounded()), 1)
            return PriceQuote(name: line.name, priceCents: cents, currency: currency, store: region == .canada ? "Demo store (CA)" : "Demo store (US)", isSale: sale < 1, label: entry.label)
        }
        return PricedList(quotes: quotes, currency: currency)
    }
}

/// Picks the server when the user is signed in, the mock otherwise, and writes quotes
/// onto grocery lines so totals and budget warnings show in the list.
@MainActor
enum PriceService {
    static func source() -> PriceSource {
        AccountSession.shared.isSignedIn ? ServerPriceSource() : MockPriceSource()
    }

    static func price(_ lines: [PlannedGroceryLine], region: Region) async -> PricedList {
        if AccountSession.shared.isSignedIn, let list = try? await ServerPriceSource().quotes(for: lines, region: region), list.quotedCount > 0 {
            return list
        }
        return MockPriceSource().quoteList(for: lines, region: region)
    }

    /// Stores quotes on the grocery rows. Returns the list total in cents.
    @discardableResult
    static func apply(to groceries: [GroceryItem], region: Region) async -> PricedList {
        let lines = groceries.filter { !$0.isChecked }.map { PlannedGroceryLine(name: $0.name, quantity: $0.quantity, unit: $0.unit, category: $0.category) }
        let list = await price(lines, region: region)
        for grocery in groceries where !grocery.isChecked {
            if let quote = list.quote(for: grocery.name) {
                grocery.priceCents = quote.priceCents
                grocery.currencyCode = quote.currency
                grocery.storeName = quote.store
            }
        }
        return list
    }
}

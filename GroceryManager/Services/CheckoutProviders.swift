import Foundation

/// A delivery or pickup service the list can be sent to. Full cart hand-off needs each
/// retailer's API (done server-side once keys exist); every provider at least opens the
/// retailer with the list pre-filled in its search.
struct CheckoutProvider: Identifiable, Equatable {
    var key: String
    var name: String
    var symbol: String
    var regions: [Region]

    var id: String { key }

    static let all: [CheckoutProvider] = [
        CheckoutProvider(key: "instacart", name: "Instacart", symbol: "carrot.fill", regions: [.unitedStates, .canada]),
        CheckoutProvider(key: "walmart", name: "Walmart", symbol: "cart.fill", regions: [.unitedStates, .canada]),
        CheckoutProvider(key: "pcexpress", name: "PC Express", symbol: "bag.fill", regions: [.canada]),
        CheckoutProvider(key: "kroger", name: "Kroger", symbol: "basket.fill", regions: [.unitedStates])
    ]

    static func available(in region: Region) -> [CheckoutProvider] {
        all.filter { $0.regions.contains(region) }
    }

    /// Search deep link with the list's item names. Server-built cart links replace this when configured.
    func url(for lines: [PlannedGroceryLine], region: Region) -> URL? {
        let query = lines.map(\.name).joined(separator: key == "instacart" ? ", " : " ")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch key {
        case "instacart": return URL(string: "https://www.instacart.com/store/s?k=\(encoded)")
        case "walmart": return URL(string: "https://www.walmart.\(region == .canada ? "ca" : "com")/search?q=\(encoded)")
        case "pcexpress": return URL(string: "https://www.pcexpress.ca/search?search-bar=\(encoded)")
        case "kroger": return URL(string: "https://www.kroger.com/search?query=\(encoded)")
        default: return nil
        }
    }
}

@MainActor
enum CheckoutService {
    private struct Request: Encodable {
        struct Line: Encodable { var name: String; var quantity: Double; var unit: String }
        var provider: String
        var region: String
        var lines: [Line]
    }
    private struct Response: Decodable { var url: String }

    /// Prefers the server (it can build real carts); falls back to the client deep link.
    static func checkoutURL(provider: CheckoutProvider, lines: [PlannedGroceryLine], region: Region) async -> URL? {
        if AccountSession.shared.isSignedIn {
            let key = "\(provider.key)-\(region.rawValue.lowercased())"
            let request = Request(provider: key, region: region.rawValue, lines: lines.map { .init(name: $0.name, quantity: $0.quantity, unit: $0.unit) })
            if let response = try? await APIClient.shared.post("/api/checkout/link", body: request, as: Response.self), let url = URL(string: response.url) {
                return url
            }
        }
        return provider.url(for: lines, region: region)
    }
}

import Foundation

/// Thin client for the Next.js backend. Free users never need it; it is only used once the
/// user signs in for a paid feature (household sharing, prices, auto-planning).
struct APIClient: Sendable {
    static let shared = APIClient()

    var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "api.baseURL"), let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }

    enum APIError: LocalizedError {
        case notSignedIn
        case http(Int, String)
        case decoding

        var errorDescription: String? {
            switch self {
            case .notSignedIn: "Sign in to use this feature."
            case .http(let code, let message): "Server error \(code): \(message)"
            case .decoding: "The server sent an unexpected response."
            }
        }
    }

    func get<T: Decodable>(_ path: String, as type: T.Type, authorized: Bool = true) async throws -> T {
        try await request("GET", path, body: Optional<Data>.none, authorized: authorized)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B, as type: T.Type, authorized: Bool = true) async throws -> T {
        try await request("POST", path, body: try JSONEncoder.api.encode(body), authorized: authorized)
    }

    private func request<T: Decodable>(_ method: String, _ path: String, body: Data?, authorized: Bool) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            guard let token = await AccountSession.shared.accessToken else { throw APIError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? ""
            throw APIError.http(status, message)
        }
        do {
            return try JSONDecoder.api.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// The signed-in account, if any. Tokens live in the keychain-backed defaults suite for now.
@MainActor
@Observable
final class AccountSession {
    static let shared = AccountSession()

    private let defaults = UserDefaults.standard

    var accessToken: String? {
        get { defaults.string(forKey: "account.accessToken") }
        set { defaults.set(newValue, forKey: "account.accessToken") }
    }

    var userID: String? {
        get { defaults.string(forKey: "account.userID") }
        set { defaults.set(newValue, forKey: "account.userID") }
    }

    var email: String? {
        get { defaults.string(forKey: "account.email") }
        set { defaults.set(newValue, forKey: "account.email") }
    }

    var isSignedIn: Bool { accessToken != nil }

    func signOut() {
        accessToken = nil
        userID = nil
        email = nil
        Task { await EntitlementService.shared.refresh() }
    }
}

/// Reads `/api/entitlements` for signed-in users. The server has already reconciled
/// App Store and Stripe subscriptions, so this answer wins over local StoreKit state.
struct ServerEntitlementProvider: EntitlementProvider {
    struct Response: Decodable {
        var tier: String
        var expiresAt: Date?
        var source: String
        var isInGracePeriod: Bool?
        var productId: String?
    }

    func currentSnapshot() async -> EntitlementSnapshot? {
        guard await AccountSession.shared.isSignedIn else { return nil }
        guard let response = try? await APIClient.shared.get("/api/entitlements", as: Response.self) else { return nil }
        return EntitlementSnapshot(
            tier: Tier(rawValue: response.tier) ?? .free,
            expiresAt: response.expiresAt,
            source: .server,
            fetchedAt: .now,
            isInGracePeriod: response.isInGracePeriod ?? false,
            productID: response.productId ?? ""
        )
    }
}

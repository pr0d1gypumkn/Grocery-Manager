import Foundation
import AuthenticationServices
import CryptoKit
import Security
import StoreKit

/// Thin client for the Next.js backend. Free users never need it; it is only used once the
/// user signs in for a paid feature (household sharing, prices, auto-planning).
struct APIClient: Sendable {
    static let shared = APIClient()

    /// The backend for this build, from the `MEALY_API_BASE_URL` build setting (Info.plist
    /// `MealyAPIBaseURL`). Release builds leave it empty until the server is deployed, and
    /// every server-backed feature hides itself while it is `nil`.
    var baseURL: URL? {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "api.baseURL"), let url = URL(string: override) {
            return url
        }
        #endif
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MealyAPIBaseURL") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: raw), url.scheme != nil else { return nil }
        return url
    }

    /// Whether this build has a server to talk to.
    static var isConfigured: Bool { shared.baseURL != nil }

    enum APIError: LocalizedError {
        case notSignedIn
        case notConfigured
        case http(Int, String)
        case decoding

        var errorDescription: String? {
            switch self {
            case .notSignedIn: "Sign in to use this feature."
            case .notConfigured: "This feature isn't available yet."
            case .http(_, let message) where !message.isEmpty: message
            case .http(let code, _): "Something went wrong (error \(code)). Please try again."
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

    func delete<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await request("DELETE", path, body: Optional<Data>.none, authorized: true)
    }

    private func request<T: Decodable>(_ method: String, _ path: String, body: Data?, authorized: Bool) async throws -> T {
        guard let baseURL else { throw APIError.notConfigured }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = await AccountSession.shared.accessToken {
            // Also sent on sign-in calls, so the server links an Apple ID to the current user.
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if authorized {
            throw APIError.notSignedIn
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

/// The signed-in account, if any. The session token lives in the Keychain; the
/// non-secret profile fields live in UserDefaults.
@MainActor
@Observable
final class AccountSession {
    static let shared = AccountSession()

    private let defaults = UserDefaults.standard

    /// Mirrors the Keychain so SwiftUI observes sign-in changes.
    private var cachedToken: String? = Keychain.read("account.accessToken")

    init() {
        // Move a token saved by older builds out of UserDefaults.
        if let legacy = defaults.string(forKey: "account.accessToken") {
            if cachedToken == nil { accessToken = legacy }
            defaults.removeObject(forKey: "account.accessToken")
        }
    }

    var accessToken: String? {
        get { cachedToken }
        set {
            cachedToken = newValue
            if let newValue { Keychain.write(newValue, for: "account.accessToken") } else { Keychain.delete("account.accessToken") }
        }
    }

    var userID: String? {
        get { defaults.string(forKey: "account.userID") }
        set { defaults.set(newValue, forKey: "account.userID") }
    }

    var email: String? {
        get { defaults.string(forKey: "account.email") }
        set { defaults.set(newValue, forKey: "account.email") }
    }

    var isSignedIn: Bool { APIClient.isConfigured && accessToken != nil }

    func signOut() {
        accessToken = nil
        userID = nil
        email = nil
        Task { await EntitlementService.shared.refresh() }
    }

    struct SessionResponse: Decodable { var token: String; var userId: String; var email: String? }

    private func apply(_ session: SessionResponse) async {
        accessToken = session.token
        userID = session.userId
        email = session.email
        await EntitlementService.shared.refresh()
    }

    /// Signs a subscriber in with no UI: the signed App Store transaction is the identity,
    /// so their Apple ID is the whole login. Safe to call often; it does nothing when
    /// already signed in, there's no server, or there's no subscription.
    func signInFromPurchaseIfNeeded() async {
        guard APIClient.isConfigured, !isSignedIn else { return }
        struct Body: Encodable { var signedTransaction: String; var appAccountToken: String }
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  SubscriptionProduct.ids.contains(transaction.productID) else { continue }
            let body = Body(signedTransaction: result.jwsRepresentation, appAccountToken: SubscriptionStore.appAccountToken().uuidString)
            if let session = try? await APIClient.shared.post("/api/auth/app-store", body: body, as: SessionResponse.self, authorized: false) {
                await apply(session)
                return
            }
        }
    }

    /// The raw nonce for the Sign in with Apple request in flight. Apple embeds its SHA-256
    /// in the identity token and the server checks it, so a stolen token can't be replayed.
    private var pendingNonce: String?

    /// Configures the Apple ID request (call from `SignInWithAppleButton`'s request closure).
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        pendingNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Finishes Sign in with Apple against the server.
    func completeSignInWithApple(_ result: Result<ASAuthorization, Error>) async throws {
        let authorization = try result.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken, let identityToken = String(data: tokenData, encoding: .utf8),
              let nonce = pendingNonce else {
            throw APIClient.APIError.decoding
        }
        pendingNonce = nil
        struct Body: Encodable { var identityToken: String; var nonce: String; var authorizationCode: String? }
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        let session = try await APIClient.shared.post("/api/auth/apple", body: Body(identityToken: identityToken, nonce: nonce, authorizationCode: code), as: SessionResponse.self, authorized: false)
        await apply(session)
    }

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Permanently deletes the server account and everything it owns, then signs out.
    /// On-device and iCloud data are untouched. App Store subscriptions must be
    /// cancelled by the user in their Apple account; the server can't do that.
    func deleteAccount() async throws {
        struct Reply: Decodable { var ok: Bool }
        _ = try await APIClient.shared.delete("/api/account", as: Reply.self)
        signOut()
    }
}

/// Minimal Keychain wrapper for small secrets (generic passwords, this device only).
enum Keychain {
    private static let service = "work.pumpkinpatch.mealy"

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    static func read(_ key: String) -> String? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
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

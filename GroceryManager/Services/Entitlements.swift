import Foundation
import Observation

// MARK: - Feature catalog

/// Every paid capability in the app. The raw value is the key the server uses too,
/// so `hasFeature(user, "price_aware_shopping")` means the same thing on both sides.
enum Feature: String, CaseIterable, Codable, Identifiable {
    case priceAwareShopping = "price_aware_shopping"
    case automaticPlanning = "automatic_planning"
    case recipeSuggestions = "recipe_suggestions"
    case socialImport = "social_import"
    case householdSharing = "household_sharing"
    case checkoutLinks = "checkout_links"

    var id: String { rawValue }

    /// The lowest tier that unlocks the feature.
    var tier: Tier { .plus }

    /// Whether this build can actually deliver the feature. Unavailable features are not
    /// sold, not shown on the paywall, and never unlock, so nothing paid is a placeholder.
    @MainActor
    var isAvailable: Bool {
        switch self {
        // No real price source yet; the only data would be made-up demo prices.
        case .priceAwareShopping: false
        // Needs the Mealy server for accounts and sync.
        case .householdSharing: APIClient.isConfigured
        // Work on-device; the server only improves them when present.
        case .automaticPlanning, .recipeSuggestions, .socialImport, .checkoutLinks: true
        }
    }

    /// The features this build sells, in display order.
    @MainActor
    static var available: [Feature] { allCases.filter(\.isAvailable) }

    var title: String {
        switch self {
        case .priceAwareShopping: "Price-aware shopping"
        case .automaticPlanning: "Automatic planning"
        case .recipeSuggestions: "New recipe ideas"
        case .socialImport: "Social & photo import"
        case .householdSharing: "Household sharing"
        case .checkoutLinks: "Grocery checkout"
        }
    }

    var summary: String {
        switch self {
        case .priceAwareShopping: "See what your list will cost, plan around this week's flyer prices, and set a weekly budget."
        case .automaticPlanning: "Get a full week planned from your recipes, tastes, pantry and household. Swap any meal."
        case .recipeSuggestions: "Discover recipes you haven't saved yet, matched to your tastes and what's in the pantry."
        case .socialImport: "Pull recipes out of TikTok, Instagram and YouTube links, screenshots, photos and handwritten cards."
        case .householdSharing: "Share plans, lists and the pantry with your household in real time, with portions per person."
        case .checkoutLinks: "Open your list in Instacart, PC Express, Walmart and more to shop for delivery or pickup."
        }
    }

    var symbol: String {
        switch self {
        case .priceAwareShopping: "dollarsign.circle.fill"
        case .automaticPlanning: "wand.and.stars"
        case .recipeSuggestions: "sparkles"
        case .socialImport: "camera.viewfinder"
        case .householdSharing: "person.2.fill"
        case .checkoutLinks: "shippingbox.fill"
        }
    }
}

enum Tier: String, Codable, Comparable, CaseIterable {
    case free
    case plus

    private var rank: Int {
        switch self {
        case .free: 0
        case .plus: 1
        }
    }

    static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rank < rhs.rank }

    var displayName: String {
        switch self {
        case .free: "Free"
        case .plus: "Plus"
        }
    }
}

// MARK: - Snapshot

/// What we currently believe about the user's subscription. Produced by providers
/// (StoreKit, the server) and cached locally so paid features work offline for a while.
struct EntitlementSnapshot: Codable, Equatable {
    enum Source: String, Codable {
        case none
        case appStore
        case stripe
        case server
        case debugOverride
    }

    var tier: Tier
    /// When the paid period ends. `nil` for free or for a lifetime grant.
    var expiresAt: Date?
    var source: Source
    var fetchedAt: Date
    /// Apple keeps access alive during billing retry; the server tells us when that applies.
    var isInGracePeriod: Bool = false
    var productID: String = ""

    static let free = EntitlementSnapshot(tier: .free, expiresAt: nil, source: .none, fetchedAt: .distantPast)

    /// How long a cached paid snapshot stays trusted without a fresh check.
    static let offlineGrace: TimeInterval = 7 * 24 * 60 * 60
}

// MARK: - Resolver (pure logic, unit-tested)

enum EntitlementResolver {
    /// The single rule for "is this feature on": the snapshot must be a paid tier at least as
    /// high as the feature's, not expired (grace period counts), and not stale beyond the
    /// offline allowance. A lapsed subscription simply resolves to free; data is untouched.
    static func hasFeature(_ feature: Feature, snapshot: EntitlementSnapshot?, now: Date = .now) -> Bool {
        guard let snapshot, snapshot.tier >= feature.tier, snapshot.tier != .free else { return false }
        if let expiresAt = snapshot.expiresAt, expiresAt < now, !snapshot.isInGracePeriod {
            return false
        }
        if snapshot.source != .debugOverride, now.timeIntervalSince(snapshot.fetchedAt) > EntitlementSnapshot.offlineGrace {
            return false
        }
        return true
    }

    /// Chooses the most generous snapshot when several providers answer.
    static func merge(_ snapshots: [EntitlementSnapshot], now: Date = .now) -> EntitlementSnapshot {
        let active = snapshots.filter { snapshot in
            Feature.allCases.contains { hasFeature($0, snapshot: snapshot, now: now) }
        }
        guard let best = active.max(by: { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return (lhs.expiresAt ?? .distantFuture) < (rhs.expiresAt ?? .distantFuture)
        }) else {
            return snapshots.max { $0.fetchedAt < $1.fetchedAt } ?? .free
        }
        return best
    }
}

// MARK: - Providers

protocol EntitlementProvider: Sendable {
    /// Returns `nil` when the provider has no opinion (not signed in, StoreKit unavailable).
    func currentSnapshot() async -> EntitlementSnapshot?
}

/// The one place the app asks whether a paid feature is available.
///
/// Views call `hasFeature(_:)`; nothing else should inspect tiers or receipts. Providers
/// refresh the cached snapshot in the background; the server is authoritative once the
/// user is signed in, StoreKit covers users who never create an account.
@MainActor
@Observable
final class EntitlementService {
    static let shared = EntitlementService(
        providers: [StoreKitEntitlementProvider(), ServerEntitlementProvider()],
        store: UserDefaults.standard
    )

    private(set) var snapshot: EntitlementSnapshot
    private(set) var lastRefresh: Date?
    private let providers: [EntitlementProvider]
    private let store: UserDefaults
    private let cacheKey = "entitlement.snapshot"
    private let overrideKey = "entitlement.debugOverride"

    init(providers: [EntitlementProvider], store: UserDefaults) {
        self.providers = providers
        self.store = store
        if let data = store.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(EntitlementSnapshot.self, from: data) {
            snapshot = cached
        } else {
            snapshot = .free
        }
    }

    var tier: Tier { snapshot.tier }
    var isPlus: Bool { EntitlementResolver.hasFeature(.automaticPlanning, snapshot: snapshot) }

    func hasFeature(_ feature: Feature) -> Bool {
        feature.isAvailable && EntitlementResolver.hasFeature(feature, snapshot: snapshot)
    }

    /// Re-asks every provider and keeps the most generous answer.
    func refresh() async {
        var results: [EntitlementSnapshot] = []
        for provider in providers {
            if let result = await provider.currentSnapshot() { results.append(result) }
        }
        #if DEBUG
        if let override = debugOverride { results.append(override) }
        #else
        // A demo unlock saved by a debug build must never carry into a shipped build.
        debugOverride = nil
        #endif
        let merged = EntitlementResolver.merge(results)
        apply(merged)
        lastRefresh = .now
    }

    func apply(_ newSnapshot: EntitlementSnapshot) {
        snapshot = newSnapshot
        if let data = try? JSONEncoder().encode(newSnapshot) {
            store.set(data, forKey: cacheKey)
        }
    }

    // MARK: Debug override (demo builds)

    var debugOverride: EntitlementSnapshot? {
        get {
            guard let data = store.data(forKey: overrideKey) else { return nil }
            return try? JSONDecoder().decode(EntitlementSnapshot.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                store.set(data, forKey: overrideKey)
            } else {
                store.removeObject(forKey: overrideKey)
            }
        }
    }

    /// Lets the demo flip Plus on and off without a purchase.
    func setDemoPlus(_ enabled: Bool) {
        debugOverride = enabled
            ? EntitlementSnapshot(tier: .plus, expiresAt: nil, source: .debugOverride, fetchedAt: .now)
            : nil
        Task { await refresh() }
    }
}

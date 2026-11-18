import Foundation
import Observation
import StoreKit

/// StoreKit 2 products, purchases and the entitlement provider that reads them.
enum SubscriptionProduct: String, CaseIterable {
    case monthly = "work.pumpkinpatch.mealy.plus.monthly"
    case yearly = "work.pumpkinpatch.mealy.plus.yearly"

    static let ids = allCases.map(\.rawValue)
    static let groupID = "mealy_plus"
}

struct StoreKitEntitlementProvider: EntitlementProvider {
    func currentSnapshot() async -> EntitlementSnapshot? {
        var best: EntitlementSnapshot?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  SubscriptionProduct.ids.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            let snapshot = EntitlementSnapshot(
                tier: .plus,
                expiresAt: transaction.expirationDate,
                source: .appStore,
                fetchedAt: .now,
                isInGracePeriod: false,
                productID: transaction.productID
            )
            if best == nil || (snapshot.expiresAt ?? .distantFuture) > (best?.expiresAt ?? .distantFuture) {
                best = snapshot
            }
        }
        return best
    }
}

@MainActor
@Observable
final class SubscriptionStore {
    static let shared = SubscriptionStore()

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var purchaseError: String?
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await EntitlementService.shared.refresh()
                    await AccountSession.shared.signInFromPurchaseIfNeeded()
                }
                _ = self
            }
        }
    }

    var monthly: Product? { products.first { $0.id == SubscriptionProduct.monthly.rawValue } }
    var yearly: Product? { products.first { $0.id == SubscriptionProduct.yearly.rawValue } }

    /// "Save 33%" style label for the yearly plan, computed from the live prices.
    var yearlySavings: Int? {
        guard let monthly, let yearly else { return nil }
        let monthlyPerYear = monthly.price * 12
        guard monthlyPerYear > 0 else { return nil }
        let saving = (monthlyPerYear - yearly.price) / monthlyPerYear * 100
        let percent = NSDecimalNumber(decimal: saving).intValue
        return percent > 0 ? percent : nil
    }

    func loadProducts() async {
        guard products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: SubscriptionProduct.ids)
                .sorted { $0.price < $1.price }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseError = nil
        do {
            // Ties the App Store transaction to the account (if any) so server notifications map to the user.
            let token = Self.appAccountToken()
            if AccountSession.shared.isSignedIn {
                struct Patch: Encodable { var appleAppAccountToken: String }
                struct Reply: Decodable { var ok: Bool }
                _ = try? await APIClient.shared.post("/api/account", body: Patch(appleAppAccountToken: token.uuidString), as: Reply.self)
            }
            let result = try await product.purchase(options: [.appAccountToken(token)])
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseError = "The purchase could not be verified."
                    return false
                }
                await transaction.finish()
                await EntitlementService.shared.refresh()
                await AccountSession.shared.signInFromPurchaseIfNeeded()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    /// A stable per-install UUID sent with purchases and shared with the server.
    static func appAccountToken() -> UUID {
        let key = "appStore.appAccountToken"
        if let stored = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: stored) { return uuid }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: key)
        return uuid
    }

    func restore() async {
        try? await AppStore.sync()
        await EntitlementService.shared.refresh()
        await AccountSession.shared.signInFromPurchaseIfNeeded()
    }
}

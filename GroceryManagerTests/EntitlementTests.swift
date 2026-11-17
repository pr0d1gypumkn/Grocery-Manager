import XCTest
@testable import GroceryManager

final class EntitlementTests: XCTestCase {
    private let now = Date.now

    private func plus(expiresIn days: Double?, fetchedDaysAgo: Double = 0, grace: Bool = false, source: EntitlementSnapshot.Source = .appStore) -> EntitlementSnapshot {
        EntitlementSnapshot(
            tier: .plus,
            expiresAt: days.map { now.addingTimeInterval($0 * 86_400) },
            source: source,
            fetchedAt: now.addingTimeInterval(-fetchedDaysAgo * 86_400),
            isInGracePeriod: grace
        )
    }

    func testFreeHasNoPaidFeatures() {
        for feature in Feature.allCases {
            XCTAssertFalse(EntitlementResolver.hasFeature(feature, snapshot: .free, now: now))
            XCTAssertFalse(EntitlementResolver.hasFeature(feature, snapshot: nil, now: now))
        }
    }

    func testActivePlusUnlocksEveryFeature() {
        let snapshot = plus(expiresIn: 20)
        for feature in Feature.allCases {
            XCTAssertTrue(EntitlementResolver.hasFeature(feature, snapshot: snapshot, now: now), feature.rawValue)
        }
    }

    func testLapsedSubscriptionLocksFeaturesAgain() {
        XCTAssertFalse(EntitlementResolver.hasFeature(.householdSharing, snapshot: plus(expiresIn: -1), now: now))
    }

    func testGracePeriodKeepsAccess() {
        XCTAssertTrue(EntitlementResolver.hasFeature(.householdSharing, snapshot: plus(expiresIn: -1, grace: true), now: now))
    }

    func testStaleCacheExpiresOffline() {
        XCTAssertTrue(EntitlementResolver.hasFeature(.priceAwareShopping, snapshot: plus(expiresIn: 30, fetchedDaysAgo: 6), now: now))
        XCTAssertFalse(EntitlementResolver.hasFeature(.priceAwareShopping, snapshot: plus(expiresIn: 30, fetchedDaysAgo: 8), now: now))
    }

    func testLifetimeGrantHasNoExpiry() {
        XCTAssertTrue(EntitlementResolver.hasFeature(.automaticPlanning, snapshot: plus(expiresIn: nil), now: now))
    }

    func testMergePicksTheMostGenerousActiveSnapshot() {
        let merged = EntitlementResolver.merge([.free, plus(expiresIn: -1), plus(expiresIn: 10), plus(expiresIn: 300)], now: now)
        XCTAssertEqual(merged.expiresAt, now.addingTimeInterval(300 * 86_400))

        let allLapsed = EntitlementResolver.merge([plus(expiresIn: -1), .free], now: now)
        XCTAssertFalse(EntitlementResolver.hasFeature(.checkoutLinks, snapshot: allLapsed, now: now))
    }

    @MainActor
    func testServiceCachesSnapshotAndExposesHasFeature() async {
        let defaults = UserDefaults(suiteName: "EntitlementTests-\(UUID().uuidString)")!
        struct Fixed: EntitlementProvider {
            let snapshot: EntitlementSnapshot?
            func currentSnapshot() async -> EntitlementSnapshot? { snapshot }
        }
        let service = EntitlementService(providers: [Fixed(snapshot: plus(expiresIn: 30, source: .server))], store: defaults)
        XCTAssertFalse(service.hasFeature(.recipeSuggestions))

        await service.refresh()
        XCTAssertTrue(service.hasFeature(.recipeSuggestions))

        let reloaded = EntitlementService(providers: [], store: defaults)
        XCTAssertTrue(reloaded.hasFeature(.recipeSuggestions), "cached snapshot survives a relaunch")

        let lapsed = EntitlementService(providers: [Fixed(snapshot: plus(expiresIn: -1, source: .server))], store: defaults)
        await lapsed.refresh()
        XCTAssertFalse(lapsed.hasFeature(.recipeSuggestions))
    }

    func testFeatureKeysMatchServerContract() {
        XCTAssertEqual(Feature.priceAwareShopping.rawValue, "price_aware_shopping")
        XCTAssertEqual(Set(Feature.allCases.map(\.rawValue)).count, Feature.allCases.count)
    }
}

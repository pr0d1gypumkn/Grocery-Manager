import Foundation
import Observation
import SwiftData

/// Keeps a paid household in step with the server: push the local bundle, pull the merged
/// result. Free users never sync; their data stays in SwiftData + CloudKit.
@MainActor
@Observable
final class HouseholdSyncService {
    static let shared = HouseholdSyncService()

    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var inviteCode: String?
    /// True when this user joined someone else's household. Members share through the
    /// owner's Plus, so they can sync without a subscription of their own.
    private(set) var isMemberOfSharedHousehold = false

    private struct SyncResponse: Decodable {
        var householdId: String
        var bundle: ExportBundle
    }

    private struct HouseholdResponse: Decodable {
        struct Member: Decodable { var name: String; var email: String?; var role: String }
        var id: String
        var name: String
        var inviteCode: String
        var isOwner: Bool?
        var members: [Member]
    }

    var canSync: Bool {
        AccountSession.shared.isSignedIn
            && (EntitlementService.shared.hasFeature(.householdSharing) || isMemberOfSharedHousehold)
    }

    /// Push then pull. Returns a one-line summary for a toast.
    @discardableResult
    func sync(modelContext: ModelContext, settings: AppSettings) async -> String {
        guard canSync else { return "Household sharing needs Mealy Plus, or an invite from someone who has it." }
        guard !isSyncing else { return "Already syncing" }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        do {
            let preferences = ExportBundle.Preferences(region: settings.region.rawValue, unitSystem: settings.unitSystem.rawValue, weeklyBudgetCents: settings.weeklyBudgetCents, dietTags: settings.dietTags)
            let local = DataExporter(modelContext: modelContext).bundle(preferences: preferences)
            let response = try await APIClient.shared.post("/api/sync", body: local, as: SyncResponse.self)
            let summary = DataImporter(modelContext: modelContext).importBundle(response.bundle)
            if let household = ((try? modelContext.fetch(FetchDescriptor<Household>())) ?? []).first {
                household.remoteID = response.householdId
                try? modelContext.save()
            }
            lastSync = .now
            return summary.total == 0 ? "Household is up to date" : "Synced: \(summary.description.replacingOccurrences(of: "Imported ", with: ""))"
        } catch {
            lastError = error.localizedDescription
            return error.localizedDescription
        }
    }

    func refreshInvite() async {
        guard let household = try? await APIClient.shared.get("/api/household", as: HouseholdResponse.self) else { return }
        inviteCode = household.inviteCode
        isMemberOfSharedHousehold = household.isOwner == false
    }

    func join(code: String) async throws {
        struct Response: Decodable { var householdId: String; var name: String }
        _ = try await APIClient.shared.post("/api/household/join", body: ["code": code], as: Response.self)
        isMemberOfSharedHousehold = true
    }
}

import Foundation
import SwiftData

/// The people meals are planned for. Free users have one local household; paid users
/// can share it with other accounts through the server.
@Model
final class Household {
    var name: String = "My household"
    var createdAt: Date = Date.now
    /// Server-side id once the household is shared. Empty while local-only.
    var remoteID: String = ""

    @Relationship(deleteRule: .cascade, inverse: \HouseholdMember.household)
    var storedMembers: [HouseholdMember]? = []

    var members: [HouseholdMember] {
        get { storedMembers ?? [] }
        set { storedMembers = newValue }
    }

    /// How many recipe servings one meal for everyone needs, e.g. 2 adults + 1 child = 2.5.
    var servingsPerMeal: Double {
        let total = members.reduce(0) { $0 + $1.portionMultiplier }
        return total > 0 ? total : 2
    }

    init(name: String = "My household") {
        self.name = name
    }
}

@Model
final class HouseholdMember {
    var name: String = ""
    /// 1 = a standard serving. 0.5 for a small child, 1.5 for a big eater.
    var portionMultiplier: Double = 1
    /// Comma-separated diet tags, e.g. "vegetarian, nut-free".
    var dietTags: String = ""
    var sortOrder: Int = 0
    /// Account id when the member is a signed-in user sharing the household.
    var userID: String = ""
    var household: Household?

    init(name: String, portionMultiplier: Double = 1, dietTags: String = "", sortOrder: Int = 0) {
        self.name = name
        self.portionMultiplier = portionMultiplier
        self.dietTags = dietTags
        self.sortOrder = sortOrder
    }
}

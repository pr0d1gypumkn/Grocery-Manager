import Foundation
import UserNotifications

struct ExpiryNotificationPlan: Equatable {
    let identifier: String
    let title: String
    let body: String
    let date: Date
}

struct ExpiryNotificationPlanner {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func plans(for ingredients: [Ingredient], now: Date = .now) -> [ExpiryNotificationPlan] {
        let cutoff = calendar.date(byAdding: .day, value: 3, to: now) ?? now

        return ingredients
            .filter { $0.expiryDate >= now && $0.expiryDate <= cutoff }
            .sorted { $0.expiryDate < $1.expiryDate }
            .map { ingredient in
                ExpiryNotificationPlan(
                    identifier: "ingredient-expiry-\(ingredient.persistentModelID)",
                    title: "Ingredient expiring soon",
                    body: "\(ingredient.name) expires on \(ingredient.expiryDate.formatted(date: .abbreviated, time: .omitted)).",
                    date: ingredient.expiryDate
                )
            }
    }
}

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let center: UNUserNotificationCenter
    private let planner: ExpiryNotificationPlanner

    init(
        center: UNUserNotificationCenter = .current(),
        planner: ExpiryNotificationPlanner = ExpiryNotificationPlanner()
    ) {
        self.center = center
        self.planner = planner
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func scheduleExpiryNotifications(for ingredients: [Ingredient], now: Date = .now) async throws {
        let plans = planner.plans(for: ingredients, now: now)
        let identifiers = plans.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for plan in plans {
            var dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.date)
            dateComponents.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
            try await center.add(request)
        }
    }
}

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

    /// One alert per item expiring within three days. When saved recipes could use the item,
    /// the alert suggests the best one, so the notification is a nudge to cook, not just a warning.
    func plans(for ingredients: [Ingredient], recipes: [Recipe] = [], now: Date = .now) -> [ExpiryNotificationPlan] {
        let cutoff = calendar.date(byAdding: .day, value: 3, to: now) ?? now

        return ingredients
            .filter { $0.expiryDate >= now && $0.expiryDate <= cutoff && $0.quantity > 0 }
            .sorted { $0.expiryDate < $1.expiryDate }
            .map { ingredient in
                var body = "\(ingredient.name) expires on \(ingredient.expiryDate.formatted(date: .abbreviated, time: .omitted))."
                if let suggestion = UseItUpSuggester.suggestions(recipes: recipes, inventory: [ingredient], now: now, horizonDays: 3, limit: 1).first {
                    body += " Use it up: \(suggestion.recipe.name)."
                }
                return ExpiryNotificationPlan(
                    identifier: "ingredient-expiry-\(ingredient.persistentModelID)",
                    title: ingredient.isPreparedMeal ? "Leftovers to finish" : "Ingredient expiring soon",
                    body: body,
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

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Keeps alerts in step with stock without asking again; call after stock changes.
    func rescheduleIfAuthorized(for ingredients: [Ingredient], recipes: [Recipe]) async {
        guard await isAuthorized() else { return }
        try? await scheduleExpiryNotifications(for: ingredients, recipes: recipes)
    }

    func scheduleExpiryNotifications(for ingredients: [Ingredient], recipes: [Recipe] = [], now: Date = .now) async throws {
        let plans = planner.plans(for: ingredients, recipes: recipes, now: now)
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("ingredient-expiry-") }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        for plan in plans {
            // Alert the morning before, at 9:00, so there is time to cook it.
            let alertDay = Calendar.current.date(byAdding: .day, value: -1, to: plan.date) ?? plan.date
            var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: max(alertDay, now))
            dateComponents.hour = 9
            dateComponents.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
            try await center.add(request)
        }
    }

    /// A one-off countdown for a prep-session timer.
    func scheduleTimer(id: String, title: String, seconds: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = "Timer done"
        content.body = title
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "prep-timer-\(id)", content: content, trigger: trigger))
    }

    func cancelTimer(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["prep-timer-\(id)"])
    }
}

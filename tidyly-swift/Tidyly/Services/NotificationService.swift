import Foundation
import UserNotifications

enum NotificationService {
    private static let dailyReminderId = "tidyly.daily-reminder"

    static func setEnabled(_ enabled: Bool) async throws -> Bool {
        let center = UNUserNotificationCenter.current()

        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [dailyReminderId])
            center.removeDeliveredNotifications(withIdentifiers: [dailyReminderId])
            return false
        }

        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        guard granted else {
            center.removePendingNotificationRequests(withIdentifiers: [dailyReminderId])
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Tidyly"
        content.body = "Take a moment to check today’s cleaning tasks."
        content.sound = .default

        var reminderTime = DateComponents()
        reminderTime.hour = 9
        reminderTime.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: reminderTime, repeats: true)
        let request = UNNotificationRequest(identifier: dailyReminderId, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderId])
        try await center.add(request)
        return true
    }
}

import Foundation
import UserNotifications

enum NotificationPermissionStatus: Equatable {
    case notDetermined, denied, authorized
}

enum NotificationServiceError: LocalizedError {
    case permissionDenied
    var errorDescription: String? { "Notification permission is denied. Enable Tidyly in iPhone Settings → Notifications." }
}

enum NotificationService {
    private static let prefix = "tidyly.task."

    static func permissionStatus() async -> NotificationPermissionStatus {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .authorized
        default: return .denied
        }
    }

    static func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    static func disableAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) || $0 == "tidyly.daily-reminder" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    static func reconcile(tasks: [Task], rooms: [Room], settings: Settings) async throws {
        await disableAll()
        guard settings.notificationsEnabled else { return }
        switch await permissionStatus() {
        case .notDetermined:
            // Launch owns the initial permission prompt. Do not report a denial
            // while the system has not asked the user yet.
            return
        case .denied:
            throw NotificationServiceError.permissionDenied
        case .authorized:
            break
        }

        let roomsById = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
        let eligible = tasks.filter { task in
            task.remindersEnabled && (task.isGeneralHouseholdTask || (roomsById[task.roomId]?.remindersEnabled ?? false))
        }.sorted { $0.nextDueAt < $1.nextDueAt }

        // iOS allows 64 pending local notifications. Reserve two per nearest task.
        for task in eligible.prefix(settings.overdueFollowUpsEnabled ? 30 : 60) {
            let hour = task.reminderHour ?? settings.defaultReminderHour
            let minute = task.reminderMinute ?? settings.defaultReminderMinute
            if let fireDate = scheduledDate(day: task.nextDueAt, hour: hour, minute: minute), fireDate > Date() {
                try await add(task: task, room: roomsById[task.roomId], date: fireDate, followUp: false)
            }
            if settings.overdueFollowUpsEnabled,
               let originalFollowUpDay = Calendar.current.date(byAdding: .day, value: 1, to: task.nextDueAt) {
                let followUpDay = scheduledDate(day: originalFollowUpDay, hour: hour, minute: minute).map { $0 > Date() ? originalFollowUpDay : Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() } ?? originalFollowUpDay
                if let followUpDate = scheduledDate(day: followUpDay, hour: hour, minute: minute), followUpDate > Date() {
                try await add(task: task, room: roomsById[task.roomId], date: followUpDate, followUp: true)
                }
            }
        }
    }

    private static func scheduledDate(day: Date, hour: Int, minute: Int) -> Date? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = hour; components.minute = minute
        return Calendar.current.date(from: components)
    }

    private static func add(task: Task, room: Room?, date: Date, followUp: Bool) async throws {
        let content = UNMutableNotificationContent()
        content.title = followUp ? "Task overdue" : "Cleaning reminder"
        content.body = followUp ? "\(task.title) is still due in \(room?.name ?? "your home")." : "Time for \(task.title) in \(room?.name ?? "your home")."
        content.sound = .default
        content.userInfo = ["taskId": task.id.uuidString, "roomId": task.roomId.uuidString]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let suffix = followUp ? ".followup" : ".due"
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: prefix + task.id.uuidString + suffix, content: content, trigger: trigger))
    }
}

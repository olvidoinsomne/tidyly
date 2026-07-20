import Foundation
import SwiftData

@Model final class StoredRoom {
    var id: UUID = UUID(); var name: String = ""; var icon: String = "🧹"; var color: String = "#3B82F6"; var sortOrder: Int = 0; var createdAt: Date = Date(); var remindersEnabled: Bool = true
    init(id: UUID = UUID(), name: String, icon: String, color: String, sortOrder: Int = 0, createdAt: Date = Date(), remindersEnabled: Bool = true) { self.id = id; self.name = name; self.icon = icon; self.color = color; self.sortOrder = sortOrder; self.createdAt = createdAt; self.remindersEnabled = remindersEnabled }
}

@Model final class StoredTask {
    var id: UUID = UUID(); var roomId: UUID = UUID(); var title: String = ""; var frequencyDays: Int = 7; var priority: String = Priority.medium.rawValue; var estimatedMinutes: Int = 10; var lastDoneAt: Date?; var nextDueAt: Date = Date(); var sortOrder: Int = 0; var createdAt: Date = Date(); var remindersEnabled: Bool = true; var reminderHour: Int?; var reminderMinute: Int?
    init(id: UUID = UUID(), roomId: UUID, title: String, frequencyDays: Int, priority: Priority, estimatedMinutes: Int, lastDoneAt: Date? = nil, nextDueAt: Date, sortOrder: Int = 0, createdAt: Date = Date(), remindersEnabled: Bool = true, reminderHour: Int? = nil, reminderMinute: Int? = nil) { self.id = id; self.roomId = roomId; self.title = title; self.frequencyDays = frequencyDays; self.priority = priority.rawValue; self.estimatedMinutes = estimatedMinutes; self.lastDoneAt = lastDoneAt; self.nextDueAt = nextDueAt; self.sortOrder = sortOrder; self.createdAt = createdAt; self.remindersEnabled = remindersEnabled; self.reminderHour = reminderHour; self.reminderMinute = reminderMinute }
}

@Model final class StoredCompletion {
    var id: UUID = UUID(); var taskId: UUID = UUID(); var roomId: UUID = UUID(); var completedAt: Date = Date(); var createdAt: Date = Date()
    init(id: UUID = UUID(), taskId: UUID, roomId: UUID, completedAt: Date, createdAt: Date = Date()) { self.id = id; self.taskId = taskId; self.roomId = roomId; self.completedAt = completedAt; self.createdAt = createdAt }
}

@Model final class StoredActivityEvent {
    var id: UUID = UUID(); var taskId: UUID = UUID(); var roomId: UUID = UUID(); var taskTitle: String = ""; var roomName: String = ""; var eventType: String = ""; var timestamp: Date = Date(); var previousDueDate: Date?; var resultingDueDate: Date?; var previousLastDoneAt: Date?; var resultingLastDoneAt: Date?; var completionId: UUID?
    init(id: UUID = UUID(), taskId: UUID, roomId: UUID, taskTitle: String, roomName: String, eventType: ActivityEventType, timestamp: Date = Date(), previousDueDate: Date?, resultingDueDate: Date?, previousLastDoneAt: Date?, resultingLastDoneAt: Date?, completionId: UUID? = nil) { self.id = id; self.taskId = taskId; self.roomId = roomId; self.taskTitle = taskTitle; self.roomName = roomName; self.eventType = eventType.rawValue; self.timestamp = timestamp; self.previousDueDate = previousDueDate; self.resultingDueDate = resultingDueDate; self.previousLastDoneAt = previousLastDoneAt; self.resultingLastDoneAt = resultingLastDoneAt; self.completionId = completionId }
}

@Model final class StoredSettings {
    var id: Int = 1; var householdName: String = "My Home"; var darkMode: Bool = false; var notificationsEnabled: Bool = true; var weekStartsMonday: Bool = true; var updatedAt: Date = Date(); var defaultReminderHour: Int = 9; var defaultReminderMinute: Int = 0; var overdueFollowUpsEnabled: Bool = false
    init() {}
}

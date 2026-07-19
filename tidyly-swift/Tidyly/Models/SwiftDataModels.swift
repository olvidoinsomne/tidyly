import Foundation
import SwiftData

@Model final class StoredRoom {
    var id: UUID = UUID(); var name: String = ""; var icon: String = "🧹"; var color: String = "#3B82F6"; var sortOrder: Int = 0; var createdAt: Date = Date()
    init(id: UUID = UUID(), name: String, icon: String, color: String, sortOrder: Int = 0, createdAt: Date = Date()) { self.id = id; self.name = name; self.icon = icon; self.color = color; self.sortOrder = sortOrder; self.createdAt = createdAt }
}

@Model final class StoredTask {
    var id: UUID = UUID(); var roomId: UUID = UUID(); var title: String = ""; var frequencyDays: Int = 7; var priority: String = Priority.medium.rawValue; var estimatedMinutes: Int = 10; var lastDoneAt: Date?; var nextDueAt: Date = Date(); var sortOrder: Int = 0; var createdAt: Date = Date()
    init(id: UUID = UUID(), roomId: UUID, title: String, frequencyDays: Int, priority: Priority, estimatedMinutes: Int, lastDoneAt: Date? = nil, nextDueAt: Date, sortOrder: Int = 0, createdAt: Date = Date()) { self.id = id; self.roomId = roomId; self.title = title; self.frequencyDays = frequencyDays; self.priority = priority.rawValue; self.estimatedMinutes = estimatedMinutes; self.lastDoneAt = lastDoneAt; self.nextDueAt = nextDueAt; self.sortOrder = sortOrder; self.createdAt = createdAt }
}

@Model final class StoredCompletion {
    var id: UUID = UUID(); var taskId: UUID = UUID(); var roomId: UUID = UUID(); var completedAt: Date = Date(); var createdAt: Date = Date()
    init(id: UUID = UUID(), taskId: UUID, roomId: UUID, completedAt: Date, createdAt: Date = Date()) { self.id = id; self.taskId = taskId; self.roomId = roomId; self.completedAt = completedAt; self.createdAt = createdAt }
}

@Model final class StoredSettings {
    var id: Int = 1; var householdName: String = "My Home"; var darkMode: Bool = false; var notificationsEnabled: Bool = true; var weekStartsMonday: Bool = true; var updatedAt: Date = Date()
    init() {}
}

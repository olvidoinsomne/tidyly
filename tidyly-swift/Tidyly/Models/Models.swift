import Foundation

private enum ModelDate {
    static func dateOnly(from value: String) -> Date? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))
    }

    static func dateOnlyString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

enum Priority: String, Codable, CaseIterable {
    case low, medium, high

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var color: ColorAsset {
        switch self {
        case .low: return .success
        case .medium: return .warning
        case .high: return .error
        }
    }

    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

struct Room: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var color: String
    var sortOrder: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

struct Task: Codable, Identifiable, Hashable {
    let id: UUID
    var roomId: UUID
    var title: String
    var frequencyDays: Int
    var priority: Priority
    var estimatedMinutes: Int
    var lastDoneAt: Date?
    var nextDueAt: Date
    var sortOrder: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, priority, icon
        case roomId = "room_id"
        case frequencyDays = "frequency_days"
        case estimatedMinutes = "estimated_minutes"
        case lastDoneAt = "last_done_at"
        case nextDueAt = "next_due_at"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        roomId = try c.decode(UUID.self, forKey: .roomId)
        title = try c.decode(String.self, forKey: .title)
        frequencyDays = try c.decode(Int.self, forKey: .frequencyDays)
        estimatedMinutes = try c.decode(Int.self, forKey: .estimatedMinutes)
        if c.contains(.lastDoneAt), try !c.decodeNil(forKey: .lastDoneAt) {
            if let decodedDate = try? c.decode(Date.self, forKey: .lastDoneAt) {
                lastDoneAt = decodedDate
            } else {
                let value = try c.decode(String.self, forKey: .lastDoneAt)
                lastDoneAt = ModelDate.dateOnly(from: value)
            }
        } else {
            lastDoneAt = nil
        }
        if let decodedDate = try? c.decode(Date.self, forKey: .nextDueAt) {
            nextDueAt = decodedDate
        } else {
            let value = try c.decode(String.self, forKey: .nextDueAt)
            nextDueAt = ModelDate.dateOnly(from: value) ?? Date()
        }
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        // priority comes as a string; decode manually
        if let priorityString = try? c.decode(String.self, forKey: .priority) {
            priority = Priority(rawValue: priorityString) ?? .medium
        } else {
            priority = .medium
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(roomId, forKey: .roomId)
        try c.encode(title, forKey: .title)
        try c.encode(frequencyDays, forKey: .frequencyDays)
        try c.encode(priority.rawValue, forKey: .priority)
        try c.encode(estimatedMinutes, forKey: .estimatedMinutes)
        try c.encodeIfPresent(lastDoneAt.map(ModelDate.dateOnlyString), forKey: .lastDoneAt)
        try c.encode(ModelDate.dateOnlyString(from: nextDueAt), forKey: .nextDueAt)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(createdAt, forKey: .createdAt)
    }

    init(id: UUID = UUID(), roomId: UUID, title: String, frequencyDays: Int, priority: Priority, estimatedMinutes: Int, lastDoneAt: Date? = nil, nextDueAt: Date, sortOrder: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.roomId = roomId
        self.title = title
        self.frequencyDays = frequencyDays
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.lastDoneAt = lastDoneAt
        self.nextDueAt = nextDueAt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

struct Completion: Codable, Identifiable, Hashable {
    let id: UUID
    let taskId: UUID
    let roomId: UUID
    let completedAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case roomId = "room_id"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }

    init(id: UUID = UUID(), taskId: UUID, roomId: UUID, completedAt: Date, createdAt: Date = Date()) {
        self.id = id
        self.taskId = taskId
        self.roomId = roomId
        self.completedAt = completedAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        taskId = try c.decode(UUID.self, forKey: .taskId)
        roomId = try c.decode(UUID.self, forKey: .roomId)
        if let decodedDate = try? c.decode(Date.self, forKey: .completedAt) {
            completedAt = decodedDate
        } else {
            let value = try c.decode(String.self, forKey: .completedAt)
            guard let decodedDate = ModelDate.dateOnly(from: value) else {
                throw DecodingError.dataCorruptedError(forKey: .completedAt, in: c, debugDescription: "Invalid date format: \(value)")
            }
            completedAt = decodedDate
        }
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(taskId, forKey: .taskId)
        try c.encode(roomId, forKey: .roomId)
        try c.encode(ModelDate.dateOnlyString(from: completedAt), forKey: .completedAt)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

struct Settings: Codable, Identifiable {
    let id: Int
    var householdName: String
    var darkMode: Bool
    var notificationsEnabled: Bool
    var weekStartsMonday: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case householdName = "household_name"
        case darkMode = "dark_mode"
        case notificationsEnabled = "notifications_enabled"
        case weekStartsMonday = "week_starts_monday"
        case updatedAt = "updated_at"
    }
}

struct TaskWithRoom: Identifiable, Hashable {
    let task: Task
    let room: Room

    var id: UUID { task.id }
}

struct RoomWithTasks: Identifiable, Hashable {
    let room: Room
    let tasks: [Task]
    let completionRate: Int
    let overdueCount: Int
    let dueCount: Int

    var id: UUID { room.id }
}

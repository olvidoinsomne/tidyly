import Foundation
import SwiftData
import WidgetKit

@MainActor
final class DatabaseService: ObservableObject {
    @Published var notificationError: String?
    let modelContainer: ModelContainer
    private let context: ModelContext

    init(inMemory: Bool = false) {
        let schema = Schema([StoredRoom.self, StoredTask.self, StoredCompletion.self, StoredActivityEvent.self, StoredSettings.self])
        // Local-first SwiftData store. CloudKit can be enabled here once the app
        // is signed by a paid Apple Developer team with an iCloud container.
        let configuration = ModelConfiguration(
            "Tidyly",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            context = modelContainer.mainContext
            context.autosaveEnabled = true
        } catch { fatalError("Unable to create Tidyly data store: \(error)") }
    }

    static func todayISO() -> String { isoFormatter().string(from: Date()) }
    static func isoFormatter() -> ISO8601DateFormatter { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f }
    static func addDays(_ dateStr: String, days: Int) -> String { let d = dateOnlyFormatter.date(from: dateStr) ?? Date(); return dateOnlyFormatter.string(from: Calendar.current.date(byAdding: .day, value: days, to: d) ?? d) }
    static func daysUntil(_ dateStr: String) -> Int { let today = dateOnlyFormatter.date(from: todayISO()) ?? Date(); let target = dateOnlyFormatter.date(from: dateStr) ?? Date(); return Calendar.current.dateComponents([.day], from: today, to: target).day ?? 0 }
    static func formatRelativeDate(_ dateStr: String) -> String { let d = daysUntil(dateStr); if d < 0 { return "\(abs(d))d overdue" }; if d == 0 { return "Today" }; if d == 1 { return "Tomorrow" }; if d <= 7 { return "In \(d) days" }; return monthDayFormatter.string(from: dateOnlyFormatter.date(from: dateStr) ?? Date()) }
    static func formatFullDate(_ dateStr: String) -> String { fullDateFormatter.string(from: dateOnlyFormatter.date(from: dateStr) ?? Date()) }
    static func getWeekStart(weekStartsMonday: Bool = true) -> String { let cal = Calendar.current; let today = Date(); let weekday = cal.component(.weekday, from: today); let offset = weekStartsMonday ? (weekday == 1 ? 6 : weekday - 2) : weekday - 1; return dateOnlyFormatter.string(from: cal.date(byAdding: .day, value: -offset, to: today) ?? today) }
    static func getWeekDates(_ weekStart: String) -> [String] { (0..<7).map { addDays(weekStart, days: $0) } }
    static let dateOnlyFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return f }()
    static let monthDayFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()
    static let fullDateFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f }()
    static let iso8601DateOnly: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f }()

    func fetchRooms() async throws -> [Room] { try context.fetch(FetchDescriptor<StoredRoom>(sortBy: [SortDescriptor(\.sortOrder)])).map(Self.room) }
    func fetchRoomsWithTasks() async throws -> [RoomWithTasks] {
        let allRooms = try await fetchRooms(), allTasks = try await fetchAllTasks(), today = Self.todayISO()
        return allRooms.map { room in
            let tasks = allTasks.filter { $0.roomId == room.id }
            let overdue = tasks.filter { Self.dateOnlyFormatter.string(from: $0.nextDueAt) < today }.count
            let due = tasks.filter { Self.dateOnlyFormatter.string(from: $0.nextDueAt) <= today }.count
            let completed = tasks.filter { task in guard let lastDone = task.lastDoneAt else { return false }; let next = Calendar.current.date(byAdding: .day, value: task.frequencyDays, to: lastDone) ?? Date(); return Self.dateOnlyFormatter.string(from: next) >= today }.count
            return RoomWithTasks(room: room, tasks: tasks.sorted { $0.nextDueAt < $1.nextDueAt }, completionRate: tasks.isEmpty ? 0 : Int(Double(completed) / Double(tasks.count) * 100), overdueCount: overdue, dueCount: due)
        }
    }
    func createRoom(name: String, icon: String, color: String) async throws -> Room { let order = (try context.fetch(FetchDescriptor<StoredRoom>()).map(\.sortOrder).max() ?? -1) + 1; let value = StoredRoom(name: name, icon: icon, color: color, sortOrder: order); context.insert(value); try context.save(); return Self.room(value) }
    func createRoom(name: String, icon: String, color: String, starterTasks: [TaskSuggestion]) async throws -> Room {
        let roomOrder = (try context.fetch(FetchDescriptor<StoredRoom>()).map(\.sortOrder).max() ?? -1) + 1
        let room = StoredRoom(name: name, icon: icon, color: color, sortOrder: roomOrder)
        context.insert(room)

        for (index, suggestion) in starterTasks.enumerated() {
            let nextDueAt = Self.dateOnlyFormatter.date(
                from: Self.addDays(Self.todayISO(), days: suggestion.frequencyDays / 2)
            ) ?? Date()
            context.insert(StoredTask(
                roomId: room.id,
                title: suggestion.title,
                frequencyDays: suggestion.frequencyDays,
                priority: suggestion.priority,
                estimatedMinutes: suggestion.estimatedMinutes,
                nextDueAt: nextDueAt,
                sortOrder: index
            ))
        }

        do {
            try context.save()
            publishWidgetSnapshot()
            return Self.room(room)
        } catch {
            context.rollback()
            throw error
        }
    }
    func updateRoom(id: UUID, name: String?, icon: String?, color: String?) async throws { guard let value = try storedRoom(id) else { return }; if let name { value.name = name }; if let icon { value.icon = icon }; if let color { value.color = color }; try context.save(); publishWidgetSnapshot() }
    func updateRoomReminders(id: UUID, enabled: Bool) async throws { guard let value = try storedRoom(id) else { return }; value.remindersEnabled = enabled; try context.save(); await refreshNotifications() }
    func updateRoomOrder(_ ids: [UUID]) async throws { let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) }); for room in try context.fetch(FetchDescriptor<StoredRoom>()) { if let index = order[room.id] { room.sortOrder = index } }; try context.save() }
    // Activity events are immutable snapshots and intentionally survive room deletion.
    func deleteRoom(id: UUID) async throws { try context.fetch(FetchDescriptor<StoredTask>()).filter { $0.roomId == id }.forEach(context.delete); try context.fetch(FetchDescriptor<StoredCompletion>()).filter { $0.roomId == id }.forEach(context.delete); if let room = try storedRoom(id) { context.delete(room) }; try context.save(); publishWidgetSnapshot() }

    func fetchAllTasks() async throws -> [Task] { try context.fetch(FetchDescriptor<StoredTask>(sortBy: [SortDescriptor(\.sortOrder)])).map(Self.task) }
    func fetchAllTasksWithRooms() async throws -> [TaskWithRoom] { try await attachRooms(try await fetchAllTasks()).sorted { $0.task.nextDueAt < $1.task.nextDueAt } }
    func fetchTasksForDate(_ date: String) async throws -> [TaskWithRoom] { try await attachRooms(try await fetchAllTasks().filter { Self.dateOnlyFormatter.string(from: $0.nextDueAt) <= date }).sorted { $0.task.nextDueAt < $1.task.nextDueAt } }
    func fetchTasksForWeek(_ start: String) async throws -> [TaskWithRoom] { let end = Self.addDays(start, days: 6); return try await attachRooms(try await fetchAllTasks().filter { let due = Self.dateOnlyFormatter.string(from: $0.nextDueAt); return due >= start && due <= end }).sorted { $0.task.nextDueAt < $1.task.nextDueAt } }
    func createTask(roomId: UUID, title: String, frequencyDays: Int, priority: Priority, estimatedMinutes: Int) async throws -> Task { let next = Self.dateOnlyFormatter.date(from: Self.addDays(Self.todayISO(), days: frequencyDays / 2)) ?? Date(); let existing = try context.fetch(FetchDescriptor<StoredTask>()).filter { $0.roomId == roomId }; let value = StoredTask(roomId: roomId, title: title, frequencyDays: frequencyDays, priority: priority, estimatedMinutes: estimatedMinutes, nextDueAt: next, sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1); context.insert(value); try context.save(); publishWidgetSnapshot(); return Self.task(value) }
    func updateTask(id: UUID, title: String?, frequencyDays: Int?, priority: Priority?, estimatedMinutes: Int?, roomId: UUID?) async throws { guard let value = try storedTask(id) else { return }; if let title { value.title = title }; if let frequencyDays { value.frequencyDays = frequencyDays }; if let priority { value.priority = priority.rawValue }; if let estimatedMinutes { value.estimatedMinutes = estimatedMinutes }; if let roomId { value.roomId = roomId }; try context.save(); publishWidgetSnapshot() }
    func updateTaskReminder(id: UUID, enabled: Bool, hour: Int?, minute: Int?) async throws { guard let value = try storedTask(id) else { return }; value.remindersEnabled = enabled; value.reminderHour = hour; value.reminderMinute = minute; try context.save(); await refreshNotifications() }
    // Activity events retain task and room names, so history remains readable after deletion.
    func deleteTask(id: UUID) async throws { try context.fetch(FetchDescriptor<StoredCompletion>()).filter { $0.taskId == id }.forEach(context.delete); if let task = try storedTask(id) { context.delete(task) }; try context.save(); publishWidgetSnapshot() }
    func completeTask(_ task: Task, completedDate: String? = nil) async throws -> Completion {
        let day = Self.dateOnlyFormatter.date(from: completedDate ?? Self.todayISO()) ?? Date()
        guard let stored = try storedTask(task.id) else { throw DatabaseError.taskNotFound(task.id) }
        let roomName = try storedRoom(stored.roomId)?.name ?? "Deleted room"
        stored.lastDoneAt = day
        stored.nextDueAt = Calendar.current.date(byAdding: .day, value: stored.frequencyDays, to: day) ?? day
        let completion = StoredCompletion(taskId: task.id, roomId: task.roomId, completedAt: day)
        context.insert(completion)
        context.insert(activityEvent(for: stored, roomName: roomName, type: .completed, previousDueDate: task.nextDueAt, resultingDueDate: stored.nextDueAt, previousLastDoneAt: task.lastDoneAt, resultingLastDoneAt: day, completionId: completion.id))
        do {
            try context.save()
            publishWidgetSnapshot()
            return Self.completion(completion)
        } catch {
            context.rollback()
            throw error
        }
    }

    func undoCompletion(id: UUID, taskBeforeCompletion: Task) async throws {
        guard let completion = try context.fetch(FetchDescriptor<StoredCompletion>()).first(where: { $0.id == id }) else { throw DatabaseError.completionNotFound(id) }
        guard let task = try storedTask(taskBeforeCompletion.id) else { throw DatabaseError.taskNotFound(taskBeforeCompletion.id) }
        let roomName = try storedRoom(task.roomId)?.name ?? "Deleted room"
        let completedDueDate = task.nextDueAt
        let completedLastDoneAt = task.lastDoneAt
        context.delete(completion)
        task.lastDoneAt = taskBeforeCompletion.lastDoneAt
        task.nextDueAt = taskBeforeCompletion.nextDueAt
        context.insert(activityEvent(for: task, roomName: roomName, type: .completionUndone, previousDueDate: completedDueDate, resultingDueDate: task.nextDueAt, previousLastDoneAt: completedLastDoneAt, resultingLastDoneAt: task.lastDoneAt, completionId: completion.id))
        do {
            try context.save()
            publishWidgetSnapshot()
            NotificationCenter.default.post(name: .taskScheduleDidChange, object: task.id)
        } catch { context.rollback(); throw error }
    }

    func rescheduleTask(_ task: Task, action: TaskRescheduleAction) async throws {
        guard let stored = try storedTask(task.id) else { throw DatabaseError.taskNotFound(task.id) }
        let roomName = try storedRoom(stored.roomId)?.name ?? "Deleted room"
        stored.nextDueAt = action.nextDueDate(for: task)
        let eventType: ActivityEventType
        switch action {
        case .tomorrow: eventType = .postponed
        case .skip: eventType = .skipped
        case .custom: eventType = .rescheduled
        }
        context.insert(activityEvent(for: stored, roomName: roomName, type: eventType, previousDueDate: task.nextDueAt, resultingDueDate: stored.nextDueAt, previousLastDoneAt: task.lastDoneAt, resultingLastDoneAt: stored.lastDoneAt))
        // Rescheduling is not completion: lastDoneAt and completion history remain unchanged.
        do {
            try context.save()
            publishWidgetSnapshot()
            NotificationCenter.default.post(name: .taskScheduleDidChange, object: task.id)
        } catch { context.rollback(); throw error }
    }

    func restoreTaskSchedule(_ taskBeforeRescheduling: Task) async throws {
        guard let stored = try storedTask(taskBeforeRescheduling.id) else { throw DatabaseError.taskNotFound(taskBeforeRescheduling.id) }
        let roomName = try storedRoom(stored.roomId)?.name ?? "Deleted room"
        let changedDueDate = stored.nextDueAt
        let changedLastDoneAt = stored.lastDoneAt
        stored.lastDoneAt = taskBeforeRescheduling.lastDoneAt
        stored.nextDueAt = taskBeforeRescheduling.nextDueAt
        context.insert(activityEvent(for: stored, roomName: roomName, type: .rescheduleUndone, previousDueDate: changedDueDate, resultingDueDate: stored.nextDueAt, previousLastDoneAt: changedLastDoneAt, resultingLastDoneAt: stored.lastDoneAt))
        do {
            try context.save()
            publishWidgetSnapshot()
            NotificationCenter.default.post(name: .taskScheduleDidChange, object: taskBeforeRescheduling.id)
        } catch { context.rollback(); throw error }
    }

    func fetchCompletionsInRange(startDate: String, endDate: String) async throws -> [Completion] { try context.fetch(FetchDescriptor<StoredCompletion>()).map(Self.completion).filter { let date = Self.dateOnlyFormatter.string(from: $0.completedAt); return date >= startDate && date <= endDate }.sorted { $0.completedAt < $1.completedAt } }
    func fetchCompletionByTaskAndDate(taskId: UUID, dateStr: String) async throws -> Completion? { try context.fetch(FetchDescriptor<StoredCompletion>()).first { $0.taskId == taskId && Self.dateOnlyFormatter.string(from: $0.completedAt) == dateStr }.map(Self.completion) }
    func deleteCompletion(id: UUID) async throws { guard let value = try context.fetch(FetchDescriptor<StoredCompletion>()).first(where: { $0.id == id }) else { return }; let taskId = value.taskId; context.delete(value); if let task = try storedTask(taskId) { let remaining = try context.fetch(FetchDescriptor<StoredCompletion>()).filter { $0.id != id && $0.taskId == taskId }.sorted { $0.completedAt > $1.completedAt }; task.lastDoneAt = remaining.first?.completedAt; task.nextDueAt = task.lastDoneAt.flatMap { Calendar.current.date(byAdding: .day, value: task.frequencyDays, to: $0) } ?? task.createdAt }; try context.save() }
    func fetchLastCompletionForTask(taskId: UUID) async throws -> Completion? { try context.fetch(FetchDescriptor<StoredCompletion>()).filter { $0.taskId == taskId }.max { $0.completedAt < $1.completedAt }.map(Self.completion) }

    func fetchActivityEvents() async throws -> [ActivityEvent] {
        try context.fetch(FetchDescriptor<StoredActivityEvent>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])).map(Self.activityEvent)
    }

    func refreshWidgetSnapshot() async { publishWidgetSnapshot() }

    func refreshNotifications() async {
        do {
            let settings = try await fetchSettings()
            try await NotificationService.reconcile(tasks: try await fetchAllTasks(), rooms: try await fetchRooms(), settings: settings)
            notificationError = nil
        } catch {
            notificationError = error.localizedDescription
        }
    }

    private func publishWidgetSnapshot() {
        do {
            let today = Self.todayISO()
            let tasks = try context.fetch(FetchDescriptor<StoredTask>())
            let rooms = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<StoredRoom>()).map { ($0.id, $0) })
            let completions = try context.fetch(FetchDescriptor<StoredCompletion>()).filter {
                Self.dateOnlyFormatter.string(from: $0.completedAt) == today
            }
            let dueTasks = tasks.filter { Self.dateOnlyFormatter.string(from: $0.nextDueAt) <= today }
                .sorted { $0.nextDueAt < $1.nextDueAt }
            let widgetTasks = dueTasks.prefix(3).map { task in
                let room = rooms[task.roomId]
                return TidylyWidgetTask(
                    id: task.id,
                    title: task.title,
                    roomName: room?.name ?? "Room",
                    roomIcon: room?.icon ?? "🧹",
                    isOverdue: Self.dateOnlyFormatter.string(from: task.nextDueAt) < today
                )
            }
            TidylyWidgetStore.save(TidylyWidgetSnapshot(
                generatedAt: Date(),
                remainingCount: dueTasks.count,
                completedCount: completions.count,
                remainingMinutes: dueTasks.reduce(0) { $0 + $1.estimatedMinutes },
                tasks: widgetTasks
            ))
            WidgetCenter.shared.reloadTimelines(ofKind: "TidylyTodayWidget")
            _Concurrency.Task { await refreshNotifications() }
        } catch {
            print("Widget snapshot error: \(error)")
        }
    }

    func fetchSettings() async throws -> Settings { if let value = try context.fetch(FetchDescriptor<StoredSettings>()).first { return Self.settings(value) }; let value = StoredSettings(); context.insert(value); try context.save(); return Self.settings(value) }
    func updateSettings(householdName: String?, darkMode: Bool?, notificationsEnabled: Bool?, weekStartsMonday: Bool?) async throws { let value: StoredSettings; if let existing = try context.fetch(FetchDescriptor<StoredSettings>()).first { value = existing } else { value = StoredSettings(); context.insert(value) }; if let householdName { value.householdName = householdName }; if let darkMode { value.darkMode = darkMode }; if let notificationsEnabled { value.notificationsEnabled = notificationsEnabled }; if let weekStartsMonday { value.weekStartsMonday = weekStartsMonday }; value.updatedAt = Date(); try context.save() }
    func updateReminderSettings(hour: Int, minute: Int, overdueFollowUpsEnabled: Bool) async throws { let value: StoredSettings; if let existing = try context.fetch(FetchDescriptor<StoredSettings>()).first { value = existing } else { value = StoredSettings(); context.insert(value) }; value.defaultReminderHour = hour; value.defaultReminderMinute = minute; value.overdueFollowUpsEnabled = overdueFollowUpsEnabled; value.updatedAt = Date(); try context.save(); await refreshNotifications() }

    private func storedRoom(_ id: UUID) throws -> StoredRoom? { try context.fetch(FetchDescriptor<StoredRoom>()).first { $0.id == id } }
    private func storedTask(_ id: UUID) throws -> StoredTask? { try context.fetch(FetchDescriptor<StoredTask>()).first { $0.id == id } }
    private func activityEvent(for task: StoredTask, roomName: String, type: ActivityEventType, previousDueDate: Date?, resultingDueDate: Date?, previousLastDoneAt: Date?, resultingLastDoneAt: Date?, completionId: UUID? = nil) -> StoredActivityEvent {
        return StoredActivityEvent(taskId: task.id, roomId: task.roomId, taskTitle: task.title, roomName: roomName, eventType: type, previousDueDate: previousDueDate, resultingDueDate: resultingDueDate, previousLastDoneAt: previousLastDoneAt, resultingLastDoneAt: resultingLastDoneAt, completionId: completionId)
    }
    private func attachRooms(_ tasks: [Task]) async throws -> [TaskWithRoom] { let rooms = Dictionary(uniqueKeysWithValues: try await fetchRooms().map { ($0.id, $0) }); return tasks.compactMap { task in rooms[task.roomId].map { TaskWithRoom(task: task, room: $0) } } }
    private static func room(_ value: StoredRoom) -> Room { Room(id: value.id, name: value.name, icon: value.icon, color: value.color, sortOrder: value.sortOrder, createdAt: value.createdAt, remindersEnabled: value.remindersEnabled) }
    private static func task(_ value: StoredTask) -> Task { Task(id: value.id, roomId: value.roomId, title: value.title, frequencyDays: value.frequencyDays, priority: Priority(rawValue: value.priority) ?? .medium, estimatedMinutes: value.estimatedMinutes, lastDoneAt: value.lastDoneAt, nextDueAt: value.nextDueAt, sortOrder: value.sortOrder, createdAt: value.createdAt, remindersEnabled: value.remindersEnabled, reminderHour: value.reminderHour, reminderMinute: value.reminderMinute) }
    private static func completion(_ value: StoredCompletion) -> Completion { Completion(id: value.id, taskId: value.taskId, roomId: value.roomId, completedAt: value.completedAt, createdAt: value.createdAt) }
    private static func activityEvent(_ value: StoredActivityEvent) -> ActivityEvent { ActivityEvent(id: value.id, taskId: value.taskId, roomId: value.roomId, taskTitle: value.taskTitle, roomName: value.roomName, type: ActivityEventType(rawValue: value.eventType) ?? .rescheduled, timestamp: value.timestamp, previousDueDate: value.previousDueDate, resultingDueDate: value.resultingDueDate, previousLastDoneAt: value.previousLastDoneAt, resultingLastDoneAt: value.resultingLastDoneAt, completionId: value.completionId) }
    private static func settings(_ value: StoredSettings) -> Settings { Settings(id: value.id, householdName: value.householdName, darkMode: value.darkMode, notificationsEnabled: value.notificationsEnabled, weekStartsMonday: value.weekStartsMonday, updatedAt: value.updatedAt, defaultReminderHour: value.defaultReminderHour, defaultReminderMinute: value.defaultReminderMinute, overdueFollowUpsEnabled: value.overdueFollowUpsEnabled) }
}

private enum DatabaseError: LocalizedError {
    case taskNotFound(UUID)
    case completionNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .taskNotFound: return "This task no longer exists."
        case .completionNotFound: return "This completion could not be found."
        }
    }
}

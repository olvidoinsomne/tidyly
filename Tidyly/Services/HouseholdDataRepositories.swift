import Foundation

struct HouseholdMemberRecord: Decodable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let role: String
    let canManageRooms: Bool
    let canManageTasks: Bool
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id, role
        case userId = "user_id"
        case canManageRooms = "can_manage_rooms"
        case canManageTasks = "can_manage_tasks"
        case user = "users"
    }

    private enum UserCodingKeys: String, CodingKey { case displayName = "display_name" }

    init(id: UUID, userId: UUID, role: String, canManageRooms: Bool, canManageTasks: Bool, displayName: String?) {
        self.id = id
        self.userId = userId
        self.role = role
        self.canManageRooms = canManageRooms
        self.canManageTasks = canManageTasks
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        role = try container.decode(String.self, forKey: .role)
        canManageRooms = try container.decode(Bool.self, forKey: .canManageRooms)
        canManageTasks = try container.decode(Bool.self, forKey: .canManageTasks)
        if let user = try? container.nestedContainer(keyedBy: UserCodingKeys.self, forKey: .user) {
            displayName = try user.decodeIfPresent(String.self, forKey: .displayName)
        } else {
            displayName = nil
        }
    }
}

struct HouseholdRoomRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let householdId: UUID?
    var name: String
    var icon: String
    var color: String
    var sortOrder: Int
    let updatedAt: Date
    let version: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color, version
        case householdId = "household_id"
        case sortOrder = "sort_order"
        case updatedAt = "updated_at"
    }
}

struct HouseholdTaskRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let householdId: UUID?
    var roomId: UUID?
    var assignedMembershipId: UUID?
    var title: String
    var frequencyDays: Int
    var priority: String
    var estimatedMinutes: Int
    var lastCompletedAt: Date?
    var nextDueOn: String
    var sortOrder: Int
    let updatedAt: Date
    let version: Int64?

    enum CodingKeys: String, CodingKey {
        case id, title, priority, version
        case householdId = "household_id"
        case roomId = "room_id"
        case assignedMembershipId = "assigned_membership_id"
        case frequencyDays = "frequency_days"
        case estimatedMinutes = "estimated_minutes"
        case lastCompletedAt = "last_completed_at"
        case nextDueOn = "next_due_on"
        case sortOrder = "sort_order"
        case updatedAt = "updated_at"
    }
}

struct HouseholdCompletionRecord: Decodable, Identifiable, Equatable {
    let id: UUID
    let taskId: UUID
    let roomId: UUID?
    let completedAt: Date
    let createdAt: Date
    let reversedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case roomId = "room_id"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case reversedAt = "reversed_at"
    }
}

struct LocalCompletionSyncRequest {
    let completionId: UUID
    let taskId: UUID
    let completedAt: Date
    let effectiveDate: String
}

struct LocalCompletionReversalSyncRequest {
    let completionId: UUID
    let mutationId: UUID
}

extension Notification.Name {
    static let localCompletionCommitted = Notification.Name("TidylyLocalCompletionCommitted")
    static let localCompletionReversed = Notification.Name("TidylyLocalCompletionReversed")
}

protocol HouseholdRoomRepository {
    func loadRooms(householdId: UUID) async throws -> [HouseholdRoomRecord]
}

protocol HouseholdTaskRepository {
    func loadTasks(householdId: UUID) async throws -> [HouseholdTaskRecord]
    func createTask(
        householdId: UUID,
        roomId: UUID?,
        assignedMembershipId: UUID?,
        title: String,
        frequencyDays: Int,
        priority: String,
        estimatedMinutes: Int,
        nextDueOn: String
    ) async throws -> HouseholdTaskRecord
    func updateTask(
        householdId: UUID,
        taskId: UUID,
        title: String,
        assignedMembershipId: UUID?
    ) async throws -> HouseholdTaskRecord
}

/// Keeps the existing SwiftData implementation available behind the same read seam.
/// It does not upload, merge, or otherwise bridge local records to Supabase.
@MainActor
final class LocalHouseholdRepository: HouseholdRoomRepository, HouseholdTaskRepository {
    private let database: DatabaseService

    init(database: DatabaseService) { self.database = database }

    func loadRooms(householdId: UUID) async throws -> [HouseholdRoomRecord] {
        try await database.fetchRooms().map {
            HouseholdRoomRecord(
                id: $0.id, householdId: nil, name: $0.name, icon: $0.icon,
                color: $0.color, sortOrder: $0.sortOrder, updatedAt: $0.createdAt, version: nil
            )
        }
    }

    func loadTasks(householdId: UUID) async throws -> [HouseholdTaskRecord] {
        try await database.fetchAllTasks().map {
            HouseholdTaskRecord(
                id: $0.id, householdId: nil,
                roomId: $0.isGeneralHouseholdTask ? nil : $0.roomId,
                assignedMembershipId: nil, title: $0.title,
                frequencyDays: $0.frequencyDays, priority: $0.priority.rawValue,
                estimatedMinutes: $0.estimatedMinutes,
                lastCompletedAt: $0.lastDoneAt,
                nextDueOn: DatabaseService.dateOnlyFormatter.string(from: $0.nextDueAt),
                sortOrder: $0.sortOrder, updatedAt: $0.createdAt, version: nil
            )
        }
    }

    func createTask(householdId: UUID, roomId: UUID?, assignedMembershipId: UUID?, title: String, frequencyDays: Int, priority: String, estimatedMinutes: Int, nextDueOn: String) async throws -> HouseholdTaskRecord {
        guard let roomId else {
            throw HouseholdRepositoryError.localRoomRequired
        }
        let task = try await database.createTask(
            roomId: roomId, title: title, frequencyDays: frequencyDays,
            priority: Priority(rawValue: priority) ?? .medium, estimatedMinutes: estimatedMinutes
        )
        return try await loadTasks(householdId: householdId).first { $0.id == task.id }!
    }

    func updateTask(householdId: UUID, taskId: UUID, title: String, assignedMembershipId: UUID?) async throws -> HouseholdTaskRecord {
        try await database.updateTask(id: taskId, title: title, frequencyDays: nil, priority: nil, estimatedMinutes: nil, roomId: nil)
        guard let task = try await loadTasks(householdId: householdId).first(where: { $0.id == taskId }) else {
            throw HouseholdRepositoryError.taskNotFound
        }
        return task
    }
}

enum HouseholdRepositoryError: LocalizedError {
    case localRoomRequired
    case taskNotFound

    var errorDescription: String? {
        switch self {
        case .localRoomRequired: "A local room is required for a local task."
        case .taskNotFound: "The task is no longer available."
        }
    }
}

import CloudKit
import Foundation

struct CloudTaskSnapshot {
    let rooms: [CloudRoomData]
    let tasks: [CloudTaskData]
}

struct CloudRoomData {
    let id: UUID; let name: String; let icon: String; let color: String
    let sortOrder: Int; let createdAt: Date; let updatedAt: Date
}

struct CloudTaskData {
    let id: UUID; let roomId: UUID; let title: String; let frequencyDays: Int
    let priority: String; let estimatedMinutes: Int; let lastDoneAt: Date?
    let nextDueAt: Date; let sortOrder: Int; let createdAt: Date; let updatedAt: Date
}

@MainActor
final class CloudTaskSyncService: ObservableObject {
    enum State: Equatable { case unavailable, idle, syncing, synced(Date), failed(String) }

    @Published private(set) var state: State = .unavailable
    private let container = CKContainer(identifier: CloudAccountService.containerIdentifier)
    private let defaults = UserDefaults.standard
    private weak var databaseService: DatabaseService?
    private var observers: [NSObjectProtocol] = []
    private var scheduledSync: _Concurrency.Task<Void, Never>?
    private var didStart = false

    var statusText: String {
        switch state {
        case .unavailable: return "Create or join a shared household to sync tasks."
        case .idle: return "Ready to sync"
        case .syncing: return "Syncing tasks…"
        case .synced(let date): return "Last synced \(date.formatted(date: .omitted, time: .shortened))"
        case .failed(let message): return message
        }
    }

    func start(databaseService: DatabaseService) {
        guard !didStart else { return }
        didStart = true
        self.databaseService = databaseService
        state = zoneID == nil ? .unavailable : .idle
        observers.append(NotificationCenter.default.addObserver(forName: .localCloudDataDidChange, object: nil, queue: .main) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.scheduleSync() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .householdShareAccepted, object: nil, queue: .main) { [weak self] _ in
            _Concurrency.Task { @MainActor in await self?.syncNow() }
        })
    }

    func syncNow() async {
        guard state != .syncing, let databaseService, let zoneID else { return }
        state = .syncing
        do {
            let database = cloudDatabase
            try await pushPendingDeletions(database: database, zoneID: zoneID)
            let remote = try await fetchSnapshot(database: database, zoneID: zoneID)
            let isFirstParticipantImport = defaults.string(forKey: "cloud.databaseScope") == "shared" && !defaults.bool(forKey: "cloud.initialImportComplete")
            if isFirstParticipantImport {
                if try databaseService.hasLocalHouseholdContent() {
                    throw SyncError.localContentNeedsDecision
                }
            }
            let knownRooms = uuidSet(forKey: "cloud.knownRoomIDs")
            let knownTasks = uuidSet(forKey: "cloud.knownTaskIDs")
            let remoteRoomIDs = Set(remote.rooms.map(\.id))
            let remoteTaskIDs = Set(remote.tasks.map(\.id))
            try databaseService.applyCloudSnapshot(remote, deletedRoomIDs: knownRooms.subtracting(remoteRoomIDs), deletedTaskIDs: knownTasks.subtracting(remoteTaskIDs))
            let merged = try databaseService.cloudSyncSnapshot()
            try await save(merged, database: database, zoneID: zoneID)
            defaults.set(merged.rooms.map { $0.id.uuidString }, forKey: "cloud.knownRoomIDs")
            defaults.set(merged.tasks.map { $0.id.uuidString }, forKey: "cloud.knownTaskIDs")
            defaults.set(true, forKey: "cloud.initialImportComplete")
            state = .synced(Date())
        } catch SyncError.localContentNeedsDecision {
            state = .failed("This device already has local tasks. Tidyly won’t overwrite them; use a fresh installation to join this beta household.")
        } catch {
            state = .failed(Self.userMessage(for: error))
        }
    }

    private func scheduleSync() {
        guard zoneID != nil else { return }
        scheduledSync?.cancel()
        scheduledSync = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(for: .seconds(1))
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private var zoneID: CKRecordZone.ID? {
        guard let zone = defaults.string(forKey: "cloud.householdZone"),
              let owner = defaults.string(forKey: "cloud.householdOwner") else { return nil }
        return CKRecordZone.ID(zoneName: zone, ownerName: owner)
    }

    private var cloudDatabase: CKDatabase {
        defaults.string(forKey: "cloud.databaseScope") == "shared" ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    private func fetchSnapshot(database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> CloudTaskSnapshot {
        async let roomRecords = records(type: "TidylyRoom", database: database, zoneID: zoneID)
        async let taskRecords = records(type: "TidylyTask", database: database, zoneID: zoneID)
        return try await CloudTaskSnapshot(
            rooms: roomRecords.compactMap(Self.room(from:)),
            tasks: taskRecords.compactMap(Self.task(from:))
        )
    }

    private func records(type: String, database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        var output: [CKRecord] = []
        var page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)
        do {
            page = try await database.records(matching: CKQuery(recordType: type, predicate: NSPredicate(value: true)), inZoneWith: zoneID)
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
        output.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })
        while let cursor = page.queryCursor {
            page = try await database.records(continuingMatchFrom: cursor)
            output.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })
        }
        return output
    }

    private func save(_ snapshot: CloudTaskSnapshot, database: CKDatabase, zoneID: CKRecordZone.ID) async throws {
        let roomRecords = snapshot.rooms.map { room -> CKRecord in
            let record = CKRecord(recordType: "TidylyRoom", recordID: CKRecord.ID(recordName: room.id.uuidString, zoneID: zoneID))
            record["id"] = room.id.uuidString; record["name"] = room.name; record["icon"] = room.icon; record["color"] = room.color
            record["sortOrder"] = room.sortOrder; record["createdAt"] = room.createdAt; record["updatedAt"] = room.updatedAt
            return record
        }
        let taskRecords = snapshot.tasks.map { task -> CKRecord in
            let record = CKRecord(recordType: "TidylyTask", recordID: CKRecord.ID(recordName: task.id.uuidString, zoneID: zoneID))
            record["id"] = task.id.uuidString; record["roomId"] = task.roomId.uuidString; record["title"] = task.title
            record["frequencyDays"] = task.frequencyDays; record["priority"] = task.priority; record["estimatedMinutes"] = task.estimatedMinutes
            record["lastDoneAt"] = task.lastDoneAt; record["nextDueAt"] = task.nextDueAt; record["sortOrder"] = task.sortOrder
            record["createdAt"] = task.createdAt; record["updatedAt"] = task.updatedAt
            return record
        }
        for batchStart in stride(from: 0, to: roomRecords.count + taskRecords.count, by: 200) {
            let all = roomRecords + taskRecords
            let end = min(batchStart + 200, all.count)
            _ = try await database.modifyRecords(saving: Array(all[batchStart..<end]), deleting: [], savePolicy: .changedKeys, atomically: false)
        }
    }

    private func pushPendingDeletions(database: CKDatabase, zoneID: CKRecordZone.ID) async throws {
        let roomKey = "cloud.pendingRoomDeletions"
        let taskKey = "cloud.pendingTaskDeletions"
        let roomIDs = defaults.stringArray(forKey: roomKey) ?? []
        let taskIDs = defaults.stringArray(forKey: taskKey) ?? []
        let recordIDs = roomIDs.map { CKRecord.ID(recordName: $0, zoneID: zoneID) } + taskIDs.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        guard !recordIDs.isEmpty else { return }
        _ = try await database.modifyRecords(saving: [], deleting: recordIDs, atomically: false)
        defaults.removeObject(forKey: roomKey)
        defaults.removeObject(forKey: taskKey)
    }

    private func uuidSet(forKey key: String) -> Set<UUID> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    private static func room(from record: CKRecord) -> CloudRoomData? {
        guard let idString = record["id"] as? String, let id = UUID(uuidString: idString), let name = record["name"] as? String,
              let icon = record["icon"] as? String, let color = record["color"] as? String,
              let sortOrder = record["sortOrder"] as? Int, let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else { return nil }
        return CloudRoomData(id: id, name: name, icon: icon, color: color, sortOrder: sortOrder, createdAt: createdAt, updatedAt: updatedAt)
    }

    private static func task(from record: CKRecord) -> CloudTaskData? {
        guard let idString = record["id"] as? String, let id = UUID(uuidString: idString),
              let roomString = record["roomId"] as? String, let roomId = UUID(uuidString: roomString),
              let title = record["title"] as? String, let frequencyDays = record["frequencyDays"] as? Int,
              let priority = record["priority"] as? String, let estimatedMinutes = record["estimatedMinutes"] as? Int,
              let nextDueAt = record["nextDueAt"] as? Date, let sortOrder = record["sortOrder"] as? Int,
              let createdAt = record["createdAt"] as? Date, let updatedAt = record["updatedAt"] as? Date else { return nil }
        return CloudTaskData(id: id, roomId: roomId, title: title, frequencyDays: frequencyDays, priority: priority, estimatedMinutes: estimatedMinutes, lastDoneAt: record["lastDoneAt"] as? Date, nextDueAt: nextDueAt, sortOrder: sortOrder, createdAt: createdAt, updatedAt: updatedAt)
    }

    private static func userMessage(for error: Error) -> String {
        guard let cloudError = error as? CKError else { return "Task sync failed. Please try again." }
        switch cloudError.code {
        case .notAuthenticated: return "Sign in to iCloud, then retry task sync."
        case .networkFailure, .networkUnavailable: return "Task sync is waiting for an internet connection."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud is busy. Please retry shortly."
        case .serverRecordChanged: return "Another device changed these tasks. Retry to merge the latest version."
        default: return "Task sync failed. Please try again."
        }
    }
}

private enum SyncError: Error { case localContentNeedsDecision }

extension Notification.Name {
    static let localCloudDataDidChange = Notification.Name("TidylyLocalCloudDataDidChange")
}

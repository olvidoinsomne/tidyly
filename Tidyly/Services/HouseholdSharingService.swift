import CloudKit
import Foundation

@MainActor
final class HouseholdSharingService: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case ready
        case failed(String)
    }

    static let householdRecordType = "TidylyHousehold"
    static let householdRecordName = "household"

    @Published private(set) var state: State = .idle
    @Published private(set) var share: CKShare?

    private let container: CKContainer
    private let defaults: UserDefaults

    init(
        container: CKContainer = CKContainer(identifier: CloudAccountService.containerIdentifier),
        defaults: UserDefaults = .standard
    ) {
        self.container = container
        self.defaults = defaults
    }

    var statusText: String {
        switch state {
        case .idle: return "Not shared"
        case .preparing: return "Preparing household…"
        case .ready: return "Household sharing is ready"
        case .failed(let message): return message
        }
    }

    func prepareHousehold(named name: String) async {
        guard state != .preparing else { return }
        state = .preparing
        share = nil

        let database = container.privateCloudDatabase
        var operation = "verifyAccountStatus"
        var zoneID = savedZoneID

        do {
            guard try await container.accountStatus() == .available else {
                throw HouseholdSharingError.accountUnavailable
            }

            operation = "prepareCustomZone"
            zoneID = try await ensureZone(in: database)
            guard let zoneID else { throw HouseholdSharingError.zoneWasNotSaved }

            operation = "saveHouseholdRecord"
            try await ensureHouseholdRecord(named: name, in: database, zoneID: zoneID)

            operation = "loadOrCreateZoneShare"
            share = try await loadOrCreateShare(named: name, in: database, zoneID: zoneID)
            state = .ready
        } catch {
            Self.log(error, operation: operation, zoneID: zoneID, databaseScope: "private", defaults: defaults)
            state = .failed(Self.userMessage(for: error))
        }
    }

    func refresh() async {
        guard let zoneID = savedZoneID else { return }
        state = .preparing
        do {
            guard try await container.accountStatus() == .available else {
                throw HouseholdSharingError.accountUnavailable
            }
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            share = try await container.privateCloudDatabase.record(for: shareID) as? CKShare
            guard share != nil else { throw HouseholdSharingError.shareWasNotSaved }
            state = .ready
        } catch {
            Self.log(error, operation: "refreshZoneShare", zoneID: zoneID, databaseScope: "private", defaults: defaults)
            share = nil
            state = .failed(Self.userMessage(for: error))
        }
    }

    private func ensureZone(in database: CKDatabase) async throws -> CKRecordZone.ID {
        let zoneID = savedZoneID ?? CKRecordZone.ID(
            zoneName: "TidylyHousehold-\(UUID().uuidString)",
            ownerName: CKCurrentUserDefaultName
        )

        if savedZoneID != nil {
            do {
                _ = try await database.recordZone(for: zoneID)
                return zoneID
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                Self.log(error, operation: "reloadSavedZone", zoneID: zoneID, databaseScope: "private", defaults: defaults)
                // Recreate the same deterministic zone. Never delete a zone or make a duplicate.
            }
        }

        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        save(zoneID: zoneID)
        return zoneID
    }

    private func ensureHouseholdRecord(named name: String, in database: CKDatabase, zoneID: CKRecordZone.ID) async throws {
        let householdID = savedHouseholdID ?? UUID()
        if savedHouseholdID == nil {
            // Persist identity before the network request so an interrupted retry reuses it.
            defaults.set(householdID.uuidString, forKey: "cloud.householdID")
        }

        let recordID = CKRecord.ID(recordName: Self.householdRecordName, zoneID: zoneID)
        let household: CKRecord
        do {
            household = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            household = CKRecord(recordType: Self.householdRecordType, recordID: recordID)
            household["createdAt"] = Date() as CKRecordValue
        }
        household["householdID"] = householdID.uuidString as CKRecordValue
        household["name"] = name as CKRecordValue
        household["updatedAt"] = Date() as CKRecordValue
        _ = try await database.save(household)
    }

    private func loadOrCreateShare(named name: String, in database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> CKShare {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            if let existing = try await database.record(for: shareID) as? CKShare {
                return existing
            }
            throw HouseholdSharingError.shareWasNotSaved
        } catch let error as CKError where error.code == .unknownItem {
            let newShare = CKShare(recordZoneID: zoneID)
            newShare[CKShare.SystemFieldKey.title] = name as CKRecordValue
            newShare.publicPermission = .none
            guard let savedShare = try await database.save(newShare) as? CKShare else {
                throw HouseholdSharingError.shareWasNotSaved
            }
            return savedShare
        }
    }

    private var savedZoneID: CKRecordZone.ID? {
        guard let zoneName = defaults.string(forKey: "cloud.householdZone") else { return nil }
        return CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private var savedHouseholdID: UUID? {
        defaults.string(forKey: "cloud.householdID").flatMap(UUID.init(uuidString:))
    }

    private func save(zoneID: CKRecordZone.ID) {
        defaults.set(zoneID.zoneName, forKey: "cloud.householdZone")
        defaults.set(zoneID.ownerName, forKey: "cloud.householdOwner")
        defaults.set("private", forKey: "cloud.databaseScope")
    }

    private static func userMessage(for error: Error) -> String {
        if case HouseholdSharingError.accountUnavailable = error {
            return "Sign in to iCloud, then try again."
        }
        guard let cloudError = error as? CKError else {
            return "Tidyly couldn’t prepare household sharing. Please try again."
        }
        switch cloudError.code {
        case .notAuthenticated: return "Sign in to iCloud, then try again."
        case .networkFailure, .networkUnavailable: return "Check your connection, then try again."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud is busy. Please try again shortly."
        case .permissionFailure: return "This iCloud account can’t create a household share."
        case .serverRejectedRequest:
            return "Household sharing isn’t available in this version yet. Please update Tidyly or try again later."
        case .unknownItem, .zoneNotFound:
            return "Tidyly couldn’t find the saved household in iCloud. Try again to repair it."
        case .partialFailure:
            return "iCloud saved only part of the household. Please try again to finish setup."
        default: return "Tidyly couldn’t prepare household sharing. Please try again."
        }
    }

    private static func log(
        _ error: Error,
        operation: String,
        zoneID: CKRecordZone.ID?,
        databaseScope: String,
        defaults: UserDefaults
    ) {
        #if DEBUG
        let savedValues = [
            "cloud.householdZone": defaults.string(forKey: "cloud.householdZone") ?? "nil",
            "cloud.householdOwner": defaults.string(forKey: "cloud.householdOwner") ?? "nil",
            "cloud.householdID": defaults.string(forKey: "cloud.householdID") ?? "nil",
            "cloud.databaseScope": defaults.string(forKey: "cloud.databaseScope") ?? "nil"
        ]
        guard let cloudError = error as? CKError else {
            print("[CloudKit] operation=\(operation) error=\(error) zone=\(zoneID?.zoneName ?? "nil") scope=\(databaseScope) saved=\(savedValues)")
            return
        }
        let retryAfter = cloudError.userInfo[CKErrorRetryAfterKey] ?? "nil"
        let serverMessage = cloudError.userInfo["CKErrorServerDescription"] ?? cloudError.localizedDescription
        let partialFailures = (cloudError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error])?.map {
            let code = ($0.value as? CKError)?.code.rawValue.description ?? "non-CKError"
            return "\($0.key):\(code)"
        }.joined(separator: ",") ?? "nil"
        print("[CloudKit] operation=\(operation) code=\(cloudError.code.rawValue) retryAfter=\(retryAfter) serverMessage=\(serverMessage) partialFailures=\(partialFailures) zone=\(zoneID?.zoneName ?? "nil") owner=\(zoneID?.ownerName ?? "nil") scope=\(databaseScope) saved=\(savedValues)")
        #endif
    }
}

private enum HouseholdSharingError: Error {
    case accountUnavailable
    case zoneWasNotSaved
    case shareWasNotSaved
}

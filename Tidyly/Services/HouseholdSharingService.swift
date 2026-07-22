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
        do {
            let zoneID = savedZoneID ?? CKRecordZone.ID(
                zoneName: "TidylyHousehold-\(UUID().uuidString)",
                ownerName: CKCurrentUserDefaultName
            )
            let database = container.privateCloudDatabase
            if savedZoneID == nil {
                _ = try await database.save(CKRecordZone(zoneID: zoneID))
                save(zoneID: zoneID)
            }

            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            if let existing = try? await database.record(for: shareID) as? CKShare {
                share = existing
                state = .ready
                return
            }

            let householdID = savedHouseholdID ?? UUID()
            let householdRecordID = CKRecord.ID(recordName: Self.householdRecordName, zoneID: zoneID)
            let household = CKRecord(recordType: Self.householdRecordType, recordID: householdRecordID)
            household["householdID"] = householdID.uuidString as CKRecordValue
            household["name"] = name as CKRecordValue
            household["createdAt"] = Date() as CKRecordValue

            let newShare = CKShare(recordZoneID: zoneID)
            newShare[CKShare.SystemFieldKey.title] = name as CKRecordValue
            newShare.publicPermission = .none

            let result = try await database.modifyRecords(saving: [household, newShare], deleting: [])
            guard case .success(let savedShare)? = result.saveResults[newShare.recordID],
                  let cloudShare = savedShare as? CKShare else {
                throw HouseholdSharingError.shareWasNotSaved
            }
            defaults.set(householdID.uuidString, forKey: "cloud.householdID")
            share = cloudShare
            state = .ready
        } catch {
            state = .failed(Self.userMessage(for: error))
        }
    }

    func refresh() async {
        guard let zoneID = savedZoneID else { return }
        state = .preparing
        do {
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            guard let existing = try await container.privateCloudDatabase.record(for: shareID) as? CKShare else {
                throw HouseholdSharingError.shareWasNotSaved
            }
            share = existing
            state = .ready
        } catch {
            share = nil
            state = .failed(Self.userMessage(for: error))
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
        guard let cloudError = error as? CKError else {
            return "Tidyly couldn’t prepare household sharing. Please try again."
        }
        switch cloudError.code {
        case .notAuthenticated: return "Sign in to iCloud, then try again."
        case .networkFailure, .networkUnavailable: return "Check your connection, then try again."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud is busy. Please try again shortly."
        case .permissionFailure: return "This iCloud account can’t create a household share."
        default: return "Tidyly couldn’t prepare household sharing. Please try again."
        }
    }
}

private enum HouseholdSharingError: Error {
    case shareWasNotSaved
}

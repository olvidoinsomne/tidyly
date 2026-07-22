import CloudKit
import UIKit

final class CloudShareAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let container = CKContainer(identifier: cloudKitShareMetadata.containerIdentifier)
        let operation = CKAcceptSharesOperation(shareMetadatas: [cloudKitShareMetadata])
        operation.perShareResultBlock = { _, result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    UserDefaults.standard.set(cloudKitShareMetadata.share.recordID.zoneID.zoneName, forKey: "cloud.householdZone")
                    UserDefaults.standard.set(cloudKitShareMetadata.share.recordID.zoneID.ownerName, forKey: "cloud.householdOwner")
                    UserDefaults.standard.set("shared", forKey: "cloud.databaseScope")
                    NotificationCenter.default.post(name: .householdShareAccepted, object: nil)
                case .failure(let error):
                    NotificationCenter.default.post(name: .householdShareFailed, object: error)
                }
            }
        }
        container.add(operation)
    }
}

import CloudKit
import SwiftUI
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for csc: UICloudSharingController) -> String? { "Tidyly Household" }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            NotificationCenter.default.post(name: .householdShareFailed, object: error)
        }
    }
}

extension Notification.Name {
    static let householdShareFailed = Notification.Name("TidylyHouseholdShareFailed")
    static let householdShareAccepted = Notification.Name("TidylyHouseholdShareAccepted")
}

import CloudKit
import Foundation

@MainActor
final class CloudAccountService: ObservableObject {
    enum Status: Equatable {
        case checking
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case error(String)

        var title: String {
            switch self {
            case .checking: return "Checking iCloud…"
            case .available: return "iCloud Available"
            case .noAccount: return "Sign in to iCloud"
            case .restricted: return "iCloud Restricted"
            case .temporarilyUnavailable: return "iCloud Temporarily Unavailable"
            case .error: return "iCloud Check Failed"
            }
        }

        var guidance: String {
            switch self {
            case .checking: return "Checking whether this device can use household sharing."
            case .available: return "This device can use CloudKit household sharing."
            case .noAccount: return "Sign in to iCloud in Settings to share a household."
            case .restricted: return "This device’s restrictions prevent iCloud sharing."
            case .temporarilyUnavailable: return "Try again after the iCloud service is available."
            case .error(let message): return message
            }
        }

        var isAvailable: Bool { self == .available }
    }

    nonisolated static let containerIdentifier = "iCloud.com.tidyly.jonesweb.club"

    @Published private(set) var status: Status = .checking
    private let container: CKContainer
    private var accountObserver: NSObjectProtocol?

    init(container: CKContainer = CKContainer(identifier: CloudAccountService.containerIdentifier)) {
        self.container = container
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in await self?.refresh() }
        }
    }

    deinit {
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
    }

    func refresh() async {
        status = .checking
        do {
            switch try await container.accountStatus() {
            case .available: status = .available
            case .noAccount: status = .noAccount
            case .restricted: status = .restricted
            case .temporarilyUnavailable: status = .temporarilyUnavailable
            case .couldNotDetermine:
                status = .error("Tidyly couldn’t determine the iCloud account status. Check your connection and try again.")
            @unknown default:
                status = .error("This iCloud account state isn’t supported by this version of Tidyly.")
            }
        } catch {
            status = .error(Self.userMessage(for: error))
        }
    }

    private static func userMessage(for error: Error) -> String {
        guard let cloudError = error as? CKError else {
            return "Tidyly couldn’t connect to iCloud. Check your connection and try again."
        }
        switch cloudError.code {
        case .notAuthenticated: return "Sign in to iCloud in Settings, then try again."
        case .networkFailure, .networkUnavailable: return "Check your internet connection and try again."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud is busy right now. Please try again shortly."
        default: return "Tidyly couldn’t connect to iCloud. Please try again."
        }
    }
}

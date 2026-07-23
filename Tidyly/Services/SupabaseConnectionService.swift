import AuthenticationServices
import CryptoKit
import Foundation
import Security
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SupabaseHousehold: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let timezoneId: String
    let weekStartsOn: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case timezoneId = "timezone_id"
        case weekStartsOn = "week_starts_on"
    }
}

@MainActor
final class SupabaseConnectionService: ObservableObject, HouseholdRoomRepository, HouseholdTaskRepository {
    enum State: Equatable {
        case loading
        case signedOut
        case authenticating
        case needsHousehold
        case ready(SupabaseHousehold)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var invitationURL: URL?
    @Published private(set) var invitationExpiresAt: Date?
    @Published private(set) var pendingInvitationToken: String?
    @Published private(set) var householdMembers: [HouseholdMemberRecord] = []
    @Published private(set) var sharedRooms: [HouseholdRoomRecord] = []
    @Published private(set) var sharedTasks: [HouseholdTaskRecord] = []
    @Published private(set) var sharedCompletions: [HouseholdCompletionRecord] = []
    @Published private(set) var sharedDataError: String?
    @Published private(set) var sharedDataLastLoadedAt: Date?
    @Published private(set) var isMigratingLocalData = false
    private var session: SupabaseSession?
    private var appleNonce: String?
    private var authenticationTimeoutTask: _Concurrency.Task<Void, Never>?
    private var appleAuthorizationCoordinator: AppleAuthorizationCoordinator?

    var isBusy: Bool {
        state == .loading || state == .authenticating
    }

    var currentUserId: UUID? { session?.userId }

    var statusText: String {
        switch state {
        case .loading: "Loading your shared household…"
        case .signedOut: "Sign in securely to create or join a shared household."
        case .authenticating: "Signing in with Apple…"
        case .needsHousehold: "Signed in. Create your household to begin sharing."
        case .ready(let household): "\(household.name) is connected to Supabase."
        case .failed(let message): message
        }
    }

    func restoreSession() async {
        state = .loading
        guard let stored = SupabaseSessionStore.load() else {
            state = .signedOut
            return
        }

        do {
            session = stored.isExpired ? try await refresh(stored.refreshToken) : stored
            if let session { SupabaseSessionStore.save(session) }
            try await loadHousehold()
        } catch {
            session = nil
            SupabaseSessionStore.clear()
            state = .signedOut
        }
    }

    func startAppleSignIn() {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
        state = .authenticating
        Self.debugLog("Apple authorization started")

        let coordinator = AppleAuthorizationCoordinator { [weak self] result in
            guard let self else { return }
            _Concurrency.Task { @MainActor in
                await self.completeAppleSignIn(result)
            }
        }
        appleAuthorizationCoordinator = coordinator
        coordinator.perform(request)

        authenticationTimeoutTask?.cancel()
        authenticationTimeoutTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(for: .seconds(45))
            guard !_Concurrency.Task.isCancelled, self?.state == .authenticating else { return }
            self?.appleNonce = nil
            self?.appleAuthorizationCoordinator = nil
            self?.state = .failed("Apple sign-in timed out. Please try again.")
            Self.debugLog("Apple authorization timed out")
        }
    }

    private func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        authenticationTimeoutTask?.cancel()
        authenticationTimeoutTask = nil
        appleAuthorizationCoordinator = nil
        do {
            let authorization = try result.get()
            Self.debugLog("Apple authorization delegate returned a credential")
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                throw SupabaseError.invalidAppleCredential
            }
            appleNonce = nil
            let newSession: SupabaseSession = try await request(
                path: "auth/v1/token",
                queryItems: [URLQueryItem(name: "grant_type", value: "id_token")],
                method: "POST",
                body: AppleTokenRequest(provider: "apple", idToken: identityToken, nonce: nonce),
                authorization: nil
            )
            session = newSession
            SupabaseSessionStore.save(newSession)
            if let appleName = Self.appleDisplayName(from: credential.fullName) {
                try await updateDisplayName(appleName)
            }
            Self.debugLog("Supabase session created")
            try await loadHousehold()
        } catch {
            appleNonce = nil
            if (error as? ASAuthorizationError)?.code == .canceled {
                state = .signedOut
                Self.debugLog("Apple authorization cancelled")
            } else {
                state = .failed(Self.userMessage(for: error))
                Self.debugLog("Apple sign-in failed: \(Self.debugDescription(for: error))")
            }
        }
    }

    func loadHousehold() async throws {
        guard session != nil else {
            state = .signedOut
            return
        }

        let memberships: [MembershipRow] = try await authorizedRequest(
            path: "rest/v1/household_memberships",
            queryItems: [
                URLQueryItem(name: "select", value: "household_id"),
                URLQueryItem(name: "status", value: "eq.active"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        guard let householdId = memberships.first?.householdId else {
            state = .needsHousehold
            Self.debugLog("Authenticated user needs a household")
            return
        }

        let households: [SupabaseHousehold] = try await authorizedRequest(
            path: "rest/v1/households",
            queryItems: [
                URLQueryItem(name: "select", value: "id,name,timezone_id,week_starts_on"),
                URLQueryItem(name: "id", value: "eq.\(householdId.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        guard let household = households.first else {
            throw SupabaseError.missingHousehold
        }
        state = .ready(household)
        await refreshSharedData()
        Self.debugLog("Loaded household \(household.id)")
    }

    func createHousehold(named name: String, weekStartsMonday: Bool) async {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            state = .failed("Enter a household name first.")
            return
        }

        state = .loading
        do {
            let _: UUID = try await authorizedRequest(
                path: "rest/v1/rpc/create_household",
                method: "POST",
                body: CreateHouseholdRequest(
                    name: cleanedName,
                    timezoneId: TimeZone.current.identifier,
                    weekStartsOn: weekStartsMonday ? 1 : 0
                )
            )
            try await loadHousehold()
        } catch {
            state = .failed(Self.userMessage(for: error))
        }
    }

    func createInvitation() async {
        do {
            let invitations: [InvitationResponse] = try await authorizedRequest(
                path: "rest/v1/rpc/create_household_invitation",
                method: "POST",
                body: CreateInvitationRequest(role: "member", expiresIn: "7 days")
            )
            guard let invitation = invitations.first,
                  var components = URLComponents(string: "tidyly://household-invite") else {
                throw SupabaseError.invalidResponse
            }
            components.queryItems = [URLQueryItem(name: "token", value: invitation.token)]
            invitationURL = components.url
            invitationExpiresAt = invitation.expiresAt
            Self.debugLog("Created household invitation \(invitation.id)")
        } catch {
            state = .failed(Self.userMessage(for: error))
            Self.debugLog("Invitation creation failed: \(Self.debugDescription(for: error))")
        }
    }

    func clearCreatedInvitation() {
        invitationURL = nil
        invitationExpiresAt = nil
    }

    @discardableResult
    func handleInvitationURL(_ url: URL) -> Bool {
        guard url.scheme == "tidyly",
              url.host == "household-invite",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "token" })?.value,
              token.count >= 32,
              token.count <= 512 else {
            sharedDataError = "This household invitation link is malformed. Ask the sender for a new link."
            return false
        }
        pendingInvitationToken = token
        sharedDataError = nil
        Self.debugLog("Stored pending household invitation")
        return true
    }

    func acceptPendingInvitation() async throws {
        guard let token = pendingInvitationToken else {
            throw SupabaseError.invalidInvitation
        }
        guard session != nil else {
            state = .signedOut
            throw SupabaseError.notAuthenticated
        }
        state = .loading
        do {
            let _: UUID = try await authorizedRequest(
                path: "rest/v1/rpc/accept_household_invitation",
                method: "POST",
                body: AcceptInvitationRequest(token: token)
            )
            pendingInvitationToken = nil
            try await loadHousehold()
            Self.debugLog("Accepted household invitation")
        } catch {
            state = .failed(Self.invitationMessage(for: error))
            throw error
        }
    }

    func cancelPendingInvitation() {
        pendingInvitationToken = nil
    }

    func retry() async {
        guard session != nil else {
            state = .signedOut
            return
        }
        do {
            try await loadHousehold()
        } catch {
            state = .failed(Self.userMessage(for: error))
        }
    }

    func signOut() {
        authenticationTimeoutTask?.cancel()
        authenticationTimeoutTask = nil
        appleAuthorizationCoordinator = nil
        session = nil
        appleNonce = nil
        SupabaseSessionStore.clear()
        householdMembers = []
        sharedRooms = []
        sharedTasks = []
        sharedCompletions = []
        sharedDataLastLoadedAt = nil
        state = .signedOut
    }

    func refreshSharedData() async {
        guard case .ready(let household) = state else { return }
        do {
            async let members = loadMembers(householdId: household.id)
            async let rooms = loadRooms(householdId: household.id)
            async let tasks = loadTasks(householdId: household.id)
            async let completions = loadCompletions(householdId: household.id)
            let result = try await (members, rooms, tasks, completions)
            householdMembers = result.0
            sharedRooms = result.1
            sharedTasks = result.2
            sharedCompletions = result.3
            sharedDataError = nil
            sharedDataLastLoadedAt = Date()
            Self.debugLog("Reconciled Supabase data members=\(result.0.count) rooms=\(result.1.count) tasks=\(result.2.count) completions=\(result.3.count)")
        } catch {
            sharedDataError = Self.userMessage(for: error)
            Self.debugLog("Shared-data reconciliation failed: \(Self.debugDescription(for: error))")
        }
    }

    func updateDisplayName(_ name: String) async throws {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(cleaned.count), let userId = currentUserId else {
            throw SupabaseError.invalidDisplayName
        }
        let rows: [ProfileRow] = try await authorizedRequest(
            path: "rest/v1/users",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(userId.uuidString)"),
                URLQueryItem(name: "select", value: "id,display_name")
            ],
            method: "PATCH",
            body: ProfileUpdate(displayName: cleaned),
            prefer: "return=representation"
        )
        guard !rows.isEmpty else { throw SupabaseError.invalidResponse }
        if case .ready(let household) = state {
            householdMembers = try await loadMembers(householdId: household.id)
        }
    }

    func migrateLocalData(rooms: [Room], tasks: [Task]) async throws -> LocalMigrationResult {
        guard case .ready = state else { throw SupabaseError.notAuthenticated }
        guard sharedRooms.isEmpty, sharedTasks.isEmpty else {
            throw LocalMigrationError.destinationNotEmpty
        }
        isMigratingLocalData = true
        defer { isMigratingLocalData = false }

        let payloadRooms = rooms.map(SupabaseMigrationRoom.init)
        let payloadTasks = tasks.map(SupabaseMigrationTask.init)
        let result: LocalMigrationResult = try await authorizedRequest(
            path: "rest/v1/rpc/migrate_local_household_data",
            method: "POST",
            body: LocalMigrationRequest(rooms: payloadRooms, tasks: payloadTasks)
        )
        await refreshSharedData()
        guard sharedRooms.count == result.roomCount, sharedTasks.count == result.taskCount else {
            throw LocalMigrationError.verificationFailed
        }
        return result
    }

    func loadMembers(householdId: UUID) async throws -> [HouseholdMemberRecord] {
        try await authorizedRequest(
            path: "rest/v1/household_memberships",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,role,can_manage_rooms,can_manage_tasks,users!household_memberships_user_id_fkey(display_name)"),
                URLQueryItem(name: "household_id", value: "eq.\(householdId.uuidString)"),
                URLQueryItem(name: "status", value: "eq.active"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ]
        )
    }

    func loadRooms(householdId: UUID) async throws -> [HouseholdRoomRecord] {
        try await authorizedRequest(
            path: "rest/v1/rooms",
            queryItems: [
                URLQueryItem(name: "select", value: "id,household_id,name,icon,color,sort_order,updated_at,version"),
                URLQueryItem(name: "household_id", value: "eq.\(householdId.uuidString)"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "sort_order.asc,id.asc")
            ]
        )
    }

    func loadTasks(householdId: UUID) async throws -> [HouseholdTaskRecord] {
        try await authorizedRequest(
            path: "rest/v1/tasks",
            queryItems: [
                URLQueryItem(name: "select", value: "id,household_id,room_id,assigned_membership_id,title,frequency_days,priority,estimated_minutes,last_completed_at,next_due_on,sort_order,updated_at,version"),
                URLQueryItem(name: "household_id", value: "eq.\(householdId.uuidString)"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "next_due_on.asc,sort_order.asc,id.asc")
            ]
        )
    }

    func loadCompletions(householdId: UUID) async throws -> [HouseholdCompletionRecord] {
        try await authorizedRequest(
            path: "rest/v1/task_completions",
            queryItems: [
                URLQueryItem(name: "select", value: "id,task_id,room_id,completed_at,created_at,reversed_at"),
                URLQueryItem(name: "household_id", value: "eq.\(householdId.uuidString)"),
                URLQueryItem(name: "order", value: "completed_at.asc,id.asc")
            ]
        )
    }

    func syncCompletion(_ completion: LocalCompletionSyncRequest) async throws {
        let _: UUID = try await authorizedRequest(
            path: "rest/v1/rpc/complete_task",
            method: "POST",
            body: CompleteTaskRequest(
                taskId: completion.taskId,
                completedAt: completion.completedAt,
                effectiveDate: completion.effectiveDate,
                mutationId: completion.completionId
            )
        )
        await refreshSharedData()
    }

    func syncCompletionReversal(_ reversal: LocalCompletionReversalSyncRequest) async throws {
        let _: EmptyRPCResponse = try await authorizedRequest(
            path: "rest/v1/rpc/reverse_task_completion",
            method: "POST",
            body: ReverseCompletionRequest(
                completionId: reversal.completionId,
                mutationId: reversal.mutationId
            )
        )
        await refreshSharedData()
    }

    func createTask(householdId: UUID, roomId: UUID?, assignedMembershipId: UUID?, title: String, frequencyDays: Int, priority: String, estimatedMinutes: Int, nextDueOn: String) async throws -> HouseholdTaskRecord {
        let rows: [HouseholdTaskRecord] = try await authorizedRequest(
            path: "rest/v1/tasks",
            queryItems: [URLQueryItem(name: "select", value: "id,household_id,room_id,assigned_membership_id,title,frequency_days,priority,estimated_minutes,last_completed_at,next_due_on,sort_order,updated_at,version")],
            method: "POST",
            body: SupabaseTaskInsert(
                householdId: householdId, roomId: roomId, assignedMembershipId: assignedMembershipId,
                title: title, frequencyDays: frequencyDays, priority: priority,
                estimatedMinutes: estimatedMinutes, nextDueOn: nextDueOn
            ),
            prefer: "return=representation"
        )
        guard let task = rows.first else { throw HouseholdRepositoryError.taskNotFound }
        await refreshSharedData()
        return task
    }

    func updateTask(householdId: UUID, taskId: UUID, title: String, assignedMembershipId: UUID?) async throws -> HouseholdTaskRecord {
        let rows: [HouseholdTaskRecord] = try await authorizedRequest(
            path: "rest/v1/tasks",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(taskId.uuidString)"),
                URLQueryItem(name: "household_id", value: "eq.\(householdId.uuidString)"),
                URLQueryItem(name: "select", value: "id,household_id,room_id,assigned_membership_id,title,frequency_days,priority,estimated_minutes,last_completed_at,next_due_on,sort_order,updated_at,version")
            ],
            method: "PATCH",
            body: SupabaseTaskUpdate(title: title, assignedMembershipId: assignedMembershipId),
            prefer: "return=representation"
        )
        guard let task = rows.first else { throw HouseholdRepositoryError.taskNotFound }
        await refreshSharedData()
        return task
    }

    private func refresh(_ refreshToken: String) async throws -> SupabaseSession {
        try await request(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            body: RefreshTokenRequest(refreshToken: refreshToken),
            authorization: nil
        )
    }

    private func authorizedRequest<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET"
    ) async throws -> Response {
        try await authorizedRequest(path: path, queryItems: queryItems, method: method, body: Optional<EmptyBody>.none)
    }

    private func authorizedRequest<Response: Decodable, Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: Body?,
        prefer: String? = nil
    ) async throws -> Response {
        guard var currentSession = session else { throw SupabaseError.notAuthenticated }
        if currentSession.isExpired {
            currentSession = try await refresh(currentSession.refreshToken)
            session = currentSession
            SupabaseSessionStore.save(currentSession)
        }
        return try await request(
            path: path,
            queryItems: queryItems,
            method: method,
            body: body,
            authorization: currentSession.accessToken,
            prefer: prefer
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Body?,
        authorization: String?,
        prefer: String? = nil
    ) async throws -> Response {
        var components = URLComponents(url: SupabaseConfiguration.projectURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization {
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body {
            request.httpBody = try JSONEncoder.supabase.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? JSONDecoder.supabase.decode(SupabaseErrorPayload.self, from: data)
            throw SupabaseError.server(payload?.message ?? payload?.errorDescription ?? "Request failed")
        }
        return try JSONDecoder.supabase.decode(Response.self, from: data)
    }

    private static func randomNonce(length: Int = 32) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                preconditionFailure("Unable to generate a secure Apple sign-in nonce.")
            }
            for byte in bytes where byte < alphabet.count {
                result.append(alphabet[Int(byte)])
                remaining -= 1
                if remaining == 0 { break }
            }
        }
        return result
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func appleDisplayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let name = formatter.string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func userMessage(for error: Error) -> String {
        if case SupabaseError.server(let message) = error {
            if message.localizedCaseInsensitiveContains("provider is not enabled") {
                return "Sign in with Apple still needs to be enabled in Supabase."
            }
            return message
        }
        return "Couldn’t update the shared household. Check your connection and try again."
    }

    private static func invitationMessage(for error: Error) -> String {
        guard case SupabaseError.server(let message) = error else {
            return "Couldn’t accept the invitation. Check your connection and try again."
        }
        if message.localizedCaseInsensitiveContains("expired") {
            return "This household invitation has expired. Ask the sender for a new link."
        }
        if message.localizedCaseInsensitiveContains("no longer available") {
            return "This household invitation was already used, declined, or revoked. Ask the sender for a new link."
        }
        if message.localizedCaseInsensitiveContains("not found") {
            return "This household invitation is invalid. Ask the sender for a new link."
        }
        return message
    }

    private static func debugDescription(for error: Error) -> String {
        if case SupabaseError.server(let message) = error { return message }
        return String(describing: error)
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[SupabaseHousehold] \(message)")
        #endif
    }
}

@MainActor
private final class AppleAuthorizationCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<ASAuthorization, Error>) -> Void
    private var controller: ASAuthorizationController?

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func perform(_ request: ASAuthorizationAppleIDRequest) {
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Self.debugLog("delegate success")
        self.controller = nil
        completion(.success(authorization))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Self.debugLog("delegate error: \(error)")
        self.controller = nil
        completion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            Self.debugLog("using key window presentation anchor")
            return keyWindow
        }
        if let window = scenes.flatMap(\.windows).first {
            Self.debugLog("using fallback window presentation anchor")
            return window
        }
        Self.debugLog("no active window found; using temporary presentation anchor")
        return UIWindow(frame: UIScreen.main.bounds)
        #elseif os(macOS)
        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first {
            return window
        }
        return NSWindow()
        #endif
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[AppleAuthorization] \(message)")
        #endif
    }
}

private struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let expiresAt: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date().timeIntervalSince1970 >= Double(expiresAt - 60)
    }

    var userId: UUID? {
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: data) else {
            return nil
        }
        return UUID(uuidString: payload.sub)
    }
}

private struct JWTPayload: Decodable { let sub: String }

private struct AppleTokenRequest: Encodable {
    let provider: String
    let idToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider, nonce
        case idToken = "id_token"
    }
}

private struct RefreshTokenRequest: Encodable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}

private struct CreateHouseholdRequest: Encodable {
    let name: String
    let timezoneId: String
    let weekStartsOn: Int

    enum CodingKeys: String, CodingKey {
        case name = "p_household_name"
        case timezoneId = "p_household_timezone_id"
        case weekStartsOn = "p_week_starts_on"
    }
}

private struct CreateInvitationRequest: Encodable {
    let role: String
    let expiresIn: String

    enum CodingKeys: String, CodingKey {
        case role = "p_intended_role"
        case expiresIn = "p_expires_in"
    }
}

private struct InvitationResponse: Decodable {
    let id: UUID
    let token: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "invitation_id"
        case token = "invitation_token"
        case expiresAt = "expires_at"
    }
}

private struct AcceptInvitationRequest: Encodable {
    let token: String
    enum CodingKeys: String, CodingKey { case token = "p_invitation_token" }
}

private struct SupabaseTaskInsert: Encodable {
    let householdId: UUID
    let roomId: UUID?
    let assignedMembershipId: UUID?
    let title: String
    let frequencyDays: Int
    let priority: String
    let estimatedMinutes: Int
    let nextDueOn: String

    enum CodingKeys: String, CodingKey {
        case title, priority
        case householdId = "household_id"
        case roomId = "room_id"
        case assignedMembershipId = "assigned_membership_id"
        case frequencyDays = "frequency_days"
        case estimatedMinutes = "estimated_minutes"
        case nextDueOn = "next_due_on"
    }
}

private struct SupabaseTaskUpdate: Encodable {
    let title: String
    let assignedMembershipId: UUID?
    enum CodingKeys: String, CodingKey {
        case title
        case assignedMembershipId = "assigned_membership_id"
    }
}

private struct ProfileUpdate: Encodable {
    let displayName: String
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

private struct ProfileRow: Decodable {
    let id: UUID
    let displayName: String
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private struct CompleteTaskRequest: Encodable {
    let taskId: UUID
    let completedAt: Date
    let effectiveDate: String
    let mutationId: UUID
    enum CodingKeys: String, CodingKey {
        case taskId = "p_target_task_id"
        case completedAt = "p_completed_at"
        case effectiveDate = "p_effective_date"
        case mutationId = "p_mutation_id"
    }
}

private struct ReverseCompletionRequest: Encodable {
    let completionId: UUID
    let mutationId: UUID
    enum CodingKeys: String, CodingKey {
        case completionId = "p_target_completion_id"
        case mutationId = "p_mutation_id"
    }
}

private struct EmptyRPCResponse: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard container.decodeNil() else {
            throw DecodingError.typeMismatch(
                EmptyRPCResponse.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected null RPC response")
            )
        }
    }
}

struct LocalMigrationResult: Decodable, Equatable {
    let roomCount: Int
    let taskCount: Int
    enum CodingKeys: String, CodingKey {
        case roomCount = "room_count"
        case taskCount = "task_count"
    }
}

private struct LocalMigrationRequest: Encodable {
    let rooms: [SupabaseMigrationRoom]
    let tasks: [SupabaseMigrationTask]
    enum CodingKeys: String, CodingKey {
        case rooms = "p_rooms"
        case tasks = "p_tasks"
    }
}

private struct SupabaseMigrationRoom: Encodable {
    let id: UUID
    let name: String
    let icon: String
    let color: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date

    init(_ room: Room) {
        id = room.id; name = room.name; icon = room.icon; color = room.color
        sortOrder = room.sortOrder; createdAt = room.createdAt; updatedAt = room.createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct SupabaseMigrationTask: Encodable {
    let id: UUID
    let roomId: UUID?
    let title: String
    let frequencyDays: Int
    let priority: String
    let estimatedMinutes: Int
    let lastCompletedAt: Date?
    let nextDueOn: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date

    init(_ task: Task) {
        id = task.id
        roomId = task.isGeneralHouseholdTask ? nil : task.roomId
        title = task.title; frequencyDays = task.frequencyDays
        priority = task.priority.rawValue; estimatedMinutes = task.estimatedMinutes
        lastCompletedAt = task.lastDoneAt
        let due = Calendar.current.dateComponents([.year, .month, .day], from: task.nextDueAt)
        nextDueOn = String(
            format: "%04d-%02d-%02d",
            due.year ?? 1970,
            due.month ?? 1,
            due.day ?? 1
        )
        sortOrder = task.sortOrder; createdAt = task.createdAt; updatedAt = task.createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, priority
        case roomId = "room_id"
        case frequencyDays = "frequency_days"
        case estimatedMinutes = "estimated_minutes"
        case lastCompletedAt = "last_completed_at"
        case nextDueOn = "next_due_on"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum LocalMigrationError: LocalizedError {
    case destinationNotEmpty
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .destinationNotEmpty:
            "Migration is only available when the Supabase household has no rooms or tasks."
        case .verificationFailed:
            "Supabase accepted the migration, but the verification counts did not match. Your local data was retained."
        }
    }
}

private struct MembershipRow: Decodable {
    let householdId: UUID
    enum CodingKeys: String, CodingKey { case householdId = "household_id" }
}

private struct EmptyBody: Encodable {}

private struct SupabaseErrorPayload: Decodable {
    let message: String?
    let errorDescription: String?
    enum CodingKeys: String, CodingKey {
        case message
        case errorDescription = "error_description"
    }
}

private enum SupabaseError: Error {
    case invalidAppleCredential
    case invalidResponse
    case missingHousehold
    case invalidInvitation
    case invalidDisplayName
    case notAuthenticated
    case server(String)
}

private enum SupabaseSessionStore {
    private static let service = "com.tidyly.jonesweb.club.supabase"
    private static let account = "session"

    static func save(_ session: SupabaseSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        clear()
        SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data
        ] as CFDictionary, nil)
    }

    static func load() -> SupabaseSession? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary
        var item: CFTypeRef?
        guard SecItemCopyMatching(query, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    static func clear() {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary)
    }
}

private enum SupabaseConfiguration {
    static let projectURL = URL(string: "https://ascjonkrurfqojcqerdh.supabase.co")!
    static let publishableKey = "sb_publishable_AcgUnnCXmRF3ofn-nHMObg__zC2nQaH"
}

private extension JSONEncoder {
    static let supabase: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let supabase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

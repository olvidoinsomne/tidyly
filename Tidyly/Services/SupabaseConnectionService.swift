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
final class SupabaseConnectionService: ObservableObject {
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
    private var session: SupabaseSession?
    private var appleNonce: String?
    private var authenticationTimeoutTask: _Concurrency.Task<Void, Never>?
    private var appleAuthorizationCoordinator: AppleAuthorizationCoordinator?

    var isBusy: Bool {
        state == .loading || state == .authenticating
    }

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

    func handleInvitationURL(_ url: URL) {
        guard url.scheme == "tidyly",
              url.host == "household-invite",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else { return }
        pendingInvitationToken = token
        Self.debugLog("Stored pending household invitation")
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
        let _: UUID = try await authorizedRequest(
            path: "rest/v1/rpc/accept_household_invitation",
            method: "POST",
            body: AcceptInvitationRequest(token: token)
        )
        pendingInvitationToken = nil
        try await loadHousehold()
        Self.debugLog("Accepted household invitation")
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
        state = .signedOut
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
        body: Body?
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
            authorization: currentSession.accessToken
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Body?,
        authorization: String?
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

    private static func userMessage(for error: Error) -> String {
        if case SupabaseError.server(let message) = error {
            if message.localizedCaseInsensitiveContains("provider is not enabled") {
                return "Sign in with Apple still needs to be enabled in Supabase."
            }
            return message
        }
        return "Couldn’t update the shared household. Check your connection and try again."
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
}

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

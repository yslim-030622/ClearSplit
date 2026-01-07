//
//  ClearSplitApp.swift
//  ClearSplit
//
//  Entry point + app state + routing (Login → Groups)
//

import SwiftUI
import Foundation
import Security
import Combine

// MARK: - Models

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
}

struct User: Codable, Identifiable {
    let id: UUID
    let email: String
}

struct Group: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let currency: String
    let createdAt: Date
    let updatedAt: Date
    let version: Int
    let userMembershipId: UUID?  // Current user's membership in this group
}

struct Membership: Codable, Identifiable {
    let id: UUID
    let groupId: UUID
    let userId: UUID
    let role: String
    let createdAt: Date
    let user: User?  // Embedded user info
    
    var displayName: String {
        if let email = user?.email {
            return email.components(separatedBy: "@").first ?? email
        }
        return String(userId.uuidString.prefix(8)) + "..."
    }
}

// MARK: - Member Preview Models

struct MemberPreviewRequest: Codable {
    let email: String
}

struct MemberPreviewResponse: Codable {
    let found: Bool
    let alreadyMember: Bool?
    let user: User?
    let membershipId: UUID?
    let role: String?
}

// MARK: - Settlements/Balances Models

struct Settlement: Codable, Identifiable {
    let id: UUID
    let batchId: UUID
    let fromMembership: UUID
    let toMembership: UUID
    let amountCents: Int
    let status: String
    let createdAt: Date
    
    var displayAmount: String {
        let amountInDollars = Double(amountCents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD" // TODO: use group currency
        return formatter.string(from: NSNumber(value: amountInDollars)) ?? "$\(amountInDollars)"
    }
}

struct SettlementBatch: Codable, Identifiable {
    let id: UUID
    let groupId: UUID
    let status: String
    let totalSettlements: Int
    let createdAt: Date
    let updatedAt: Date
    let version: Int
    let voidedReason: String?
    let settlements: [Settlement]?
}

// MARK: - Expense Models

struct Expense: Codable, Identifiable {
    let id: UUID
    let groupId: UUID
    let title: String
    let amountCents: Int
    let currency: String
    let paidBy: UUID
    let paidByUser: User?
    let expenseDate: String
    let createdAt: Date
    let updatedAt: Date?
    
    var displayAmount: String {
        let amountInDollars = Double(amountCents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amountInDollars)) ?? "\(currency) \(amountInDollars)"
    }
}

struct CreateExpenseRequest: Codable {
    let title: String
    let amountCents: Int
    let currency: String
    let paidBy: UUID
    let expenseDate: String  // ISO8601 date string
    let splitAmong: [UUID]
}

// MARK: - Configuration

enum APIConfig {
    static var baseURL: URL {
        if let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: urlString), !urlString.isEmpty {
            return url
        }
        #if DEBUG
        return URL(string: "http://localhost:8000")!
        #else
        fatalError("API_BASE_URL must be configured in production")
        #endif
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case unauthorized
    case decodingError(Error)
    case validationError(String)
    case serverError(Int, String?)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized - please log in again"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .validationError(let message):
            return message
        case .serverError(let code, let message):
            return message ?? "Server error (\(code))"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var user: User?
    @Published var groups: [Group] = []
    @Published var isLoading: Bool = false
    @Published var expensesByGroupId: [UUID: [Expense]] = [:]
    @Published var isLoadingExpenses: Bool = false
    @Published var membershipsByGroupId: [UUID: [Membership]] = [:]
    @Published var settlementsByGroupId: [UUID: [Settlement]] = [:]
    @Published var isLoadingBalances: Bool = false

    private let keychain = KeychainService()
    private lazy var apiClient = APIClient(
        baseURL: APIConfig.baseURL,
        tokenProvider: { [weak self] in self?.keychain.readTokens() },
        refreshHandler: { [weak self] in try await self?.refreshTokensDirectly() ?? { throw APIError.unauthorized }() }
    )

    private lazy var authService = AuthService(client: apiClient, keychain: keychain)
    private lazy var groupsService = GroupsService(client: apiClient)

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }

        guard keychain.readTokens() != nil else {
            user = nil
            return
        }

        do {
            let me = try await authService.me()
            user = me
            try await loadGroups()
        } catch {
            await logout()
        }
    }

    func signup(email: String, password: String) async throws {
        print("[AppState] Signup started for: \(email)")
        isLoading = true
        defer { isLoading = false }
        
        struct SignupRequest: Encodable { let email: String; let password: String }
        struct SignupResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let tokenType: String
            let user: User
        }
        
        print("[AppState] Calling signup API...")
        let response: SignupResponse = try await apiClient.request(
            "/auth/signup",
            method: "POST",
            body: SignupRequest(email: email, password: password),
            requiresAuth: false
        )
        
        let tokens = AuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            tokenType: response.tokenType
        )
        print("[AppState] Saving tokens...")
        keychain.saveTokens(tokens)
        user = response.user
        print("[AppState] Loading groups...")
        try await loadGroups()
        print("[AppState] Signup complete!")
    }
    
    func login(email: String, password: String) async throws {
        print("[AppState] Login started for: \(email)")
        isLoading = true
        defer { isLoading = false }

        print("[AppState] Calling authService.login...")
        let tokens = try await authService.login(email: email, password: password)
        print("[AppState] Got tokens, saving to keychain...")
        keychain.saveTokens(tokens)
        print("[AppState] Fetching user info...")
        let me = try await authService.me()
        user = me
        print("[AppState] Loading groups...")
        try await loadGroups()
        print("[AppState] Login complete!")
    }

    func logout() async {
        keychain.clearTokens()
        user = nil
        groups = []
    }

    func loadGroups() async throws {
        groups = try await groupsService.listGroups()
    }
    
    func createGroup(name: String, currency: String) async throws {
        print("[AppState] Creating group: \(name) with currency: \(currency)")
        
        struct CreateGroupRequest: Encodable {
            let name: String
            let currency: String
        }
        
        let newGroup: Group = try await apiClient.request(
            "/groups",
            method: "POST",
            body: CreateGroupRequest(name: name, currency: currency),
            requiresAuth: true
        )
        
        print("[AppState] Group created: \(newGroup.name)")
        
        // Refresh groups list
        try await loadGroups()
    }
    
    func loadExpenses(groupId: UUID) async throws {
        print("[AppState] Loading expenses for group: \(groupId)")
        isLoadingExpenses = true
        defer { isLoadingExpenses = false }
        
        let expenses = try await apiClient.getGroupExpenses(groupId: groupId)
        expensesByGroupId[groupId] = expenses
        print("[AppState] Loaded \(expenses.count) expenses")
    }
    
    func loadMembers(groupId: UUID) async throws {
        print("[Members] Loading members for group: \(groupId)")
        let members = try await apiClient.getGroupMembers(groupId: groupId)
        membershipsByGroupId[groupId] = members
        print("[Members] Loaded \(members.count) members")
    }
    
    func previewMemberInvite(groupId: UUID, email: String) async throws -> MemberPreviewResponse {
        print("[AppState] Previewing invite for: \(email)")
        return try await apiClient.previewMemberInvite(groupId: groupId, email: email)
    }
    
    func addMember(groupId: UUID, email: String) async throws {
        print("[AppState] Adding member \(email) to group: \(groupId)")
        isLoading = true
        defer { isLoading = false }
        
        let newMembership = try await apiClient.addGroupMember(groupId: groupId, email: email)
        print("[AppState] Member added: \(newMembership.id)")
        
        // Refresh members list
        try await loadMembers(groupId: groupId)
    }
    
    func getUserMembership(groupId: UUID) -> Membership? {
        guard let userId = user?.id else { return nil }
        return membershipsByGroupId[groupId]?.first(where: { $0.userId == userId })
    }
    
    func loadBalances(groupId: UUID) async throws {
        print("[Balances] Loading balances for group: \(groupId)")
        isLoadingBalances = true
        defer { isLoadingBalances = false }
        
        if let batch = try await apiClient.getLatestSettlements(groupId: groupId) {
            settlementsByGroupId[groupId] = batch.settlements ?? []
            print("[Balances] Loaded \(batch.settlements?.count ?? 0) settlements")
        } else {
            settlementsByGroupId[groupId] = []
            print("[Balances] No settlements yet (group has no balances)")
        }
    }
    
    func createExpense(groupId: UUID, request: CreateExpenseRequest) async throws {
        print("[AppState] Creating expense: \(request.title)")
        isLoading = true
        defer { isLoading = false }
        
        let expense = try await apiClient.createExpense(groupId: groupId, request: request)
        print("[AppState] Created expense: \(expense.id)")
        
        // Append to local cache
        var currentExpenses = expensesByGroupId[groupId] ?? []
        currentExpenses.insert(expense, at: 0)
        expensesByGroupId[groupId] = currentExpenses
        
        // Refresh expenses and balances after creating expense
        async let expensesTask = loadExpenses(groupId: groupId)
        async let balancesTask = loadBalances(groupId: groupId)
        
        try await expensesTask
        try await balancesTask
    }
    
    func expenses(for groupId: UUID) -> [Expense] {
        expensesByGroupId[groupId] ?? []
    }
    
    func settlements(for groupId: UUID) -> [Settlement] {
        settlementsByGroupId[groupId] ?? []
    }

    // Refresh tokens without routing through AuthService to avoid init cycles.
    private func refreshTokensDirectly() async throws -> AuthTokens {
        struct RefreshRequest: Encodable {
            let refreshToken: String
            // No custom CodingKeys - let global .convertToSnakeCase handle it
        }
        struct RefreshResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let tokenType: String
            // No custom CodingKeys - let global .convertFromSnakeCase handle it
        }

        guard let current = keychain.readTokens() else { throw APIError.unauthorized }
        let body = RefreshRequest(refreshToken: current.refreshToken)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        guard let url = URL(string: "/auth/refresh", relativeTo: APIConfig.baseURL) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverError(http.statusCode, String(data: data, encoding: .utf8))
        }

        let res = try decoder.decode(RefreshResponse.self, from: data)
        let tokens = AuthTokens(accessToken: res.accessToken, refreshToken: res.refreshToken, tokenType: res.tokenType)
        keychain.saveTokens(tokens)
        return tokens
    }
}

// MARK: - App

@main
struct ClearSplitApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Root Routing

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SwiftUI.Group {
            if appState.isLoading {
                ProgressView("Loading…")
            } else if appState.user != nil {
                GroupsListView()
            } else {
                LoginView()
            }
        }
        .task {
            await appState.bootstrap()
        }
    }
}

// MARK: - Networking & Services

private actor RefreshCoordinator {
    private var isRefreshing = false
    private var waiters: [CheckedContinuation<AuthTokens, Error>] = []

    func refresh(using handler: @Sendable () async throws -> AuthTokens) async throws -> AuthTokens {
        if isRefreshing {
            return try await withCheckedThrowingContinuation { continuation in
                waiters.append(continuation)
            }
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let tokens = try await handler()
            waiters.forEach { $0.resume(returning: tokens) }
            waiters.removeAll()
            return tokens
        } catch {
            waiters.forEach { $0.resume(throwing: error) }
            waiters.removeAll()
            throw error
        }
    }
}

final class APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: () -> AuthTokens?
    private let refreshHandler: @Sendable () async throws -> AuthTokens
    private let refreshCoordinator = RefreshCoordinator()
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        baseURL: URL,
        session: URLSession = .shared,
        tokenProvider: @escaping () -> AuthTokens?,
        refreshHandler: @escaping @Sendable () async throws -> AuthTokens
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.refreshHandler = refreshHandler
        
        // Configure decoder for FastAPI date formats
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom({ decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try various ISO8601 formats (FastAPI uses +00:00 timezone format)
            let formatters: [DateFormatter] = [
                // ISO8601 with fractional seconds and timezone
                {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.timeZone = TimeZone(secondsFromGMT: 0)
                    return f
                }(),
                // ISO8601 without fractional seconds
                {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.timeZone = TimeZone(secondsFromGMT: 0)
                    return f
                }()
            ]
            
            for formatter in formatters {
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        })
        self.decoder = decoder
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        try await performRequest(path, method: method, body: body, requiresAuth: requiresAuth, isRetry: false)
    }
    
    func getGroupExpenses(groupId: UUID) async throws -> [Expense] {
        print("[APIClient] Fetching expenses for group: \(groupId)")
        return try await request(
            "/groups/\(groupId.uuidString)/expenses",
            method: "GET",
            body: Optional<String>.none,
            requiresAuth: true
        )
    }
    
    func getGroupMembers(groupId: UUID) async throws -> [Membership] {
        print("[APIClient] Fetching members for group: \(groupId)")
        return try await request(
            "/groups/\(groupId.uuidString)/members",
            method: "GET",
            body: Optional<String>.none,
            requiresAuth: true
        )
    }
    
    func previewMemberInvite(groupId: UUID, email: String) async throws -> MemberPreviewResponse {
        print("[APIClient] Previewing invite for \(email) in group: \(groupId)")
        
        let preview: MemberPreviewResponse = try await request(
            "/groups/\(groupId.uuidString)/members/preview",
            method: "POST",
            body: MemberPreviewRequest(email: email),
            requiresAuth: true
        )
        
        print("[APIClient] Preview result: found=\(preview.found), alreadyMember=\(preview.alreadyMember ?? false)")
        return preview
    }
    
    func addGroupMember(groupId: UUID, email: String) async throws -> Membership {
        print("[APIClient] Adding member \(email) to group: \(groupId)")
        
        struct AddMemberRequest: Encodable {
            let email: String
            let role: String = "member"
        }
        
        let membership: Membership = try await request(
            "/groups/\(groupId.uuidString)/members",
            method: "POST",
            body: AddMemberRequest(email: email),
            requiresAuth: true
        )
        
        print("[APIClient] Member added successfully")
        return membership
    }
    
    func getLatestSettlements(groupId: UUID) async throws -> SettlementBatch? {
        print("[APIClient] Fetching latest settlements for group: \(groupId)")
        do {
            let batch: SettlementBatch = try await request(
                "/groups/\(groupId.uuidString)/settlements/latest",
                method: "GET",
                body: Optional<String>.none,
                requiresAuth: true
            )
            return batch
        } catch APIError.serverError(404, _) {
            // No settlements yet - this is normal for new groups
            print("[APIClient] No settlements found (404) - group has no balances yet")
            return nil
        }
    }
    
    func createExpense(groupId: UUID, request: CreateExpenseRequest) async throws -> Expense {
        print("[APIClient] Creating expense in group: \(groupId)")
        print("[APIClient] Expense: \(request.title) - $\(Double(request.amountCents)/100.0) \(request.currency)")
        return try await self.request(
            "/groups/\(groupId.uuidString)/expenses",
            method: "POST",
            body: request,
            requiresAuth: true
        )
    }

    private func performRequest<T: Decodable>(
        _ path: String,
        method: String,
        body: Encodable?,
        requiresAuth: Bool,
        isRetry: Bool
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { 
            print("[APIClient] Invalid URL for path: \(path)")
            throw APIError.invalidURL 
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth, let tokens = tokenProvider() {
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
            #if DEBUG
            if let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8) {
                print("[APIClient] Request to \(method) \(path)")
                print("[APIClient] Request body: \(bodyString)")
            }
            #endif
        }

        print("[APIClient] Sending request to: \(url.absoluteString)")
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { 
            print("[APIClient] Invalid HTTP response")
            throw APIError.invalidResponse 
        }

        print("[APIClient] Response status: \(http.statusCode)")
        
        switch http.statusCode {
        case 200..<300:
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[APIClient] Response body: \(jsonString)")
            }
            #endif
            do {
                let decoded = try decoder.decode(T.self, from: data)
                print("[APIClient] Decoding succeeded for \(T.self)")
                return decoded
            } catch {
                print("[APIClient] Decoding error: \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[APIClient] Failed to decode: \(jsonString)")
                }
                throw APIError.decodingError(error)
            }
        case 401 where requiresAuth && !isRetry:
            print("[APIClient] Got 401, attempting token refresh")
            _ = try await refreshCoordinator.refresh(using: refreshHandler)
            return try await performRequest(path, method: method, body: body, requiresAuth: requiresAuth, isRetry: true)
        default:
            let errorBody = String(data: data, encoding: .utf8)
            print("[APIClient] Error response (\(http.statusCode)): \(errorBody ?? "no body")")
            if http.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.serverError(http.statusCode, errorBody)
        }
    }

    private struct AnyEncodable: Encodable {
        let value: Encodable
        init(_ value: Encodable) { self.value = value }
        func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    }
}

final class AuthService {
    private let client: APIClient
    private let keychain: KeychainService

    init(client: APIClient, keychain: KeychainService) {
        self.client = client
        self.keychain = keychain
    }

    func login(email: String, password: String) async throws -> AuthTokens {
        struct LoginRequest: Encodable { let email: String; let password: String }
        struct LoginResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let tokenType: String
            let user: User
            // No custom CodingKeys - let global .convertFromSnakeCase handle it
        }

        let response: LoginResponse = try await client.request(
            "/auth/login",
            method: "POST",
            body: LoginRequest(email: email, password: password),
            requiresAuth: false
        )

        let tokens = AuthTokens(accessToken: response.accessToken, refreshToken: response.refreshToken, tokenType: response.tokenType)
        keychain.saveTokens(tokens)
        return tokens
    }

    func refresh() async throws -> AuthTokens {
        guard let current = keychain.readTokens() else { throw APIError.unauthorized }

        struct RefreshRequest: Encodable {
            let refreshToken: String
            // No custom CodingKeys - let global .convertToSnakeCase handle it
        }

        struct RefreshResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let tokenType: String
            // No custom CodingKeys - let global .convertFromSnakeCase handle it
        }

        let response: RefreshResponse = try await client.request(
            "/auth/refresh",
            method: "POST",
            body: RefreshRequest(refreshToken: current.refreshToken),
            requiresAuth: false
        )

        return AuthTokens(accessToken: response.accessToken, refreshToken: response.refreshToken, tokenType: response.tokenType)
    }

    func me() async throws -> User {
        try await client.request("/auth/me", method: "GET", body: Optional<String>.none)
    }
}

final class GroupsService {
    private let client: APIClient
    init(client: APIClient) { self.client = client }

    func listGroups() async throws -> [Group] {
        // Support either a bare array response or a paginated { items: [] } shape.
        if let array: [Group] = try? await client.request("/groups", method: "GET", body: Optional<String>.none) {
            return array
        } else {
            struct Response: Decodable { let items: [Group] }
            let result: Response = try await client.request("/groups", method: "GET", body: Optional<String>.none)
            return result.items
        }
    }
}

// MARK: - Keychain

struct KeychainService {
    private let service = "com.clearsplit.app"
    private let account = "auth_tokens"

    func saveTokens(_ tokens: AuthTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func readTokens() -> AuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }

    func clearTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Views

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSubmitting = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Sign in")) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Log in")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSubmitting || email.isEmpty || password.isEmpty)
                }
                
                Section {
                    NavigationLink("Create account") {
                        SignUpView()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("ClearSplit")
            .alert("Error", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func submit() async {
        print("[LoginView] Submit called with email: \(email)")
        guard !email.isEmpty, !password.isEmpty else {
            print("[LoginView] Email or password is empty")
            return
        }
        isSubmitting = true
        do {
            print("[LoginView] Calling appState.login...")
            try await appState.login(email: email, password: password)
            print("[LoginView] Login succeeded!")
        } catch {
            print("[LoginView] Login failed: \(error)")
            alertMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

struct SignUpView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    
    var body: some View {
        Form {
            Section(header: Text("Create your account")) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                SecureField("Password (min 8 characters)", text: $password)
                    .textContentType(.newPassword)
                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
            }
            
            if !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty {
                Section {
                    if password.count < 8 {
                        Text("Password must be at least 8 characters")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    if password != confirmPassword {
                        Text("Passwords do not match")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            
            Section {
                Button {
                    Task { await signUp() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign Up")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSubmitting || !isValid)
            }
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }
    
    private var isValid: Bool {
        !email.isEmpty &&
        email.contains("@") &&
        password.count >= 8 &&
        password == confirmPassword
    }
    
    private func signUp() async {
        print("[SignUpView] Sign up called with email: \(email)")
        guard isValid else {
            print("[SignUpView] Validation failed")
            return
        }
        
        isSubmitting = true
        do {
            print("[SignUpView] Calling appState.signup...")
            try await appState.signup(email: email, password: password)
            print("[SignUpView] Sign up succeeded!")
            // No need to dismiss - the user is now authenticated and will see GroupsListView
        } catch {
            print("[SignUpView] Sign up failed: \(error)")
            if let apiError = error as? APIError {
                switch apiError {
                case .serverError(_, let message):
                    alertMessage = message ?? "Server error"
                default:
                    alertMessage = apiError.localizedDescription
                }
            } else {
                alertMessage = error.localizedDescription
            }
        }
        isSubmitting = false
    }
}

struct GroupsListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var alertMessage: String?
    @State private var showingCreateGroup = false

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if appState.groups.isEmpty {
                    VStack(spacing: 10) {
                        Text("No groups yet")
                            .font(.headline)
                        Text("Tap + to create your first group")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(appState.groups) { group in
                        NavigationLink(value: group) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                    .font(.headline)
                                HStack {
                                    Text(group.currency)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(group.createdAt, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Groups")
            .navigationDestination(for: Group.self) { group in
                GroupDetailView(group: group)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Log out") { Task { await appState.logout() } }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreateGroup = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .refreshable { await refresh() }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView()
            }
            .alert("Error", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage ?? "")
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        guard appState.user != nil else { return }
        do {
            try await appState.loadGroups()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct CreateGroupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var groupName: String = ""
    @State private var selectedCurrency: String = "USD"
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    
    let currencies = ["USD", "EUR", "GBP", "JPY", "KRW", "CNY", "CAD", "AUD"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Group Details")) {
                    TextField("Group Name", text: $groupName)
                        .textInputAutocapitalization(.words)
                        .disabled(isCreating)
                    
                    Picker("Currency", selection: $selectedCurrency) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency).tag(currency)
                        }
                    }
                    .disabled(isCreating)
                }
                
                Section {
                    Button {
                        Task { await createGroup() }
                    } label: {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text("Create Group")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
    
    private func createGroup() async {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Group name is required"
            showError = true
            return
        }
        
        isCreating = true
        
        do {
            print("[CreateGroup] Creating group: \(trimmedName) with currency: \(selectedCurrency)")
            try await appState.createGroup(name: trimmedName, currency: selectedCurrency)
            print("[CreateGroup] Success!")
            dismiss()
        } catch {
            isCreating = false
            print("[CreateGroup] Failed: \(error)")
            if let apiError = error as? APIError {
                switch apiError {
                case .serverError(let code, let message):
                    errorMessage = message ?? "Server error (\(code))"
                default:
                    errorMessage = apiError.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
            showError = true
        }
    }
}

struct GroupDetailView: View {
    let group: Group
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        List {
            // Group Info Section
            Section(header: Text("Group Info")) {
                HStack {
                    Text("Currency")
                    Spacer()
                    Text(group.currency)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Created")
                    Spacer()
                    Text(group.createdAt, style: .date)
                        .foregroundStyle(.secondary)
                }
                
                NavigationLink {
                    MembersListView(group: group)
                } label: {
                    HStack {
                        Text("Members")
                        Spacer()
                        let memberCount = appState.membershipsByGroupId[group.id]?.count ?? 0
                        Text("\(memberCount)")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // Shopping Sessions Section
            Section(header: Text("Shopping Sessions")) {
                if let membershipId = group.userMembershipId {
                    NavigationLink {
                        VStack(spacing: 20) {
                            Image(systemName: "cart.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                            Text("Shopping Sessions")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("Full shopping UI coming next!")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding()
                            Text("Your membership ID:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(membershipId.uuidString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle("Shopping")
                    } label: {
                        HStack {
                            Image(systemName: "cart.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("View Shopping Sessions")
                                    .font(.headline)
                                Text("Track itemized receipts & splits")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Shopping unavailable - please re-login")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadMembers()
        }
        .task {
            await loadMembers()
        }
    }
    
    private func loadMembers() async {
        do {
            try await appState.loadMembers(groupId: group.id)
        } catch {
            print("[GroupDetail] Failed to load members: \(error)")
        }
    }
}

// MARK: - Members List View

struct MembersListView: View {
    let group: Group
    @EnvironmentObject private var appState: AppState
    @State private var showingInvite = false
    
    var body: some View {
        List {
            let members = appState.membershipsByGroupId[group.id] ?? []
            
            if members.isEmpty {
                HStack {
                    Image(systemName: "person.2")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text("No members yet")
                            .foregroundStyle(.secondary)
                            Text("Tap + to invite members")
                                .font(.caption)
                                .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 8)
            } else {
                ForEach(members) { member in
                    HStack(spacing: 12) {
                        Image(systemName: member.role == "owner" ? "crown.fill" : "person.circle.fill")
                            .foregroundStyle(member.role == "owner" ? .yellow : .blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.displayName)
                                .font(.headline)
                            
                            if let email = member.user?.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text(member.role.capitalized)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Show checkmark if it's the current user
                        if member.userId == appState.user?.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingInvite = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingInvite) {
            InviteMemberSheet(groupId: group.id)
        }
    }
}

// MARK: - Invite Member Sheet

struct InviteMemberSheet: View {
    let groupId: UUID
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var email: String = ""
    @State private var isPreviewing: Bool = false
    @State private var isInviting: Bool = false
    @State private var previewResult: MemberPreviewResponse?
    @State private var previewTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    
    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailRegex = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        let predicate = NSPredicate(format: "SELF MATCHES[c] %@", emailRegex)
        return !trimmed.isEmpty && predicate.evaluate(with: trimmed)
    }
    
    private var canSendInvite: Bool {
        guard let preview = previewResult else { return false }
        return preview.found && preview.alreadyMember != true
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .disabled(isPreviewing || isInviting)
                        .onChange(of: email) { _ in
                            // Cancel preview when email changes
                            previewTask?.cancel()
                            previewResult = nil
                        }
                } header: {
                    Text("Invite by Email")
                } footer: {
                    Text("The person must already have a ClearSplit account.")
                        .font(.caption)
                }
                
                // Check Account Button
                Section {
                    Button {
                        Task { await checkAccount() }
                    } label: {
                        HStack {
                            if isPreviewing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text("Check Account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!isValidEmail || isPreviewing || isInviting)
                }
                
                // Preview Result Card
                if let preview = previewResult {
                    Section {
                        if preview.found {
                            if preview.alreadyMember == true {
                                // Already a member
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.title2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Already a Member")
                                            .font(.headline)
                                        if let user = preview.user {
                                            Text(user.email)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let role = preview.role {
                                            Text("Current role: \(role.capitalized)")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            } else {
                                // Account found - ready to invite
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.title2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Account Found")
                                            .font(.headline)
                                            .foregroundStyle(.green)
                                        if let user = preview.user {
                                            Text(user.email)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text("Ready to invite")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } else {
                            // Not found
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.xmark")
                                    .foregroundStyle(.red)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("No Account Found")
                                        .font(.headline)
                                        .foregroundStyle(.red)
                                    Text("This person needs to sign up first")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // Send Invite Button
                if previewResult != nil {
                    Section {
                        Button {
                            Task { await inviteMember() }
                        } label: {
                            HStack {
                                if isInviting {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                }
                                Text("Send Invite")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(!canSendInvite || isInviting)
                    }
                }
            }
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        previewTask?.cancel()
                        dismiss()
                    }
                    .disabled(isInviting)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
    
    private func checkAccount() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard isValidEmail else {
            errorMessage = "Please enter a valid email address"
            showError = true
            return
        }
        
        // Cancel any existing preview
        previewTask?.cancel()
        
        isPreviewing = true
        previewResult = nil
        
        previewTask = Task {
            do {
                print("[InvitePreview] Checking account: \(trimmedEmail)")
                let preview = try await appState.previewMemberInvite(
                    groupId: groupId,
                    email: trimmedEmail
                )
                
                // Check if task was cancelled
                guard !Task.isCancelled else {
                    print("[InvitePreview] Cancelled")
                    return
                }
                
                await MainActor.run {
                    isPreviewing = false
                    previewResult = preview
                    print("[InvitePreview] Result: found=\(preview.found), alreadyMember=\(preview.alreadyMember ?? false)")
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    isPreviewing = false
                    print("[InvitePreview] Failed: \(error)")
                    
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .serverError(403, _):
                            errorMessage = "Only group owners can invite members."
                        case .unauthorized:
                            errorMessage = "Session expired. Please login again."
                        case .networkError:
                            errorMessage = "Cannot connect to server"
                        default:
                            errorMessage = apiError.localizedDescription
                        }
                    } else {
                        errorMessage = "Failed to check account"
                    }
                    showError = true
                }
            }
        }
    }
    
    private func inviteMember() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard canSendInvite else {
            return
        }
        
        isInviting = true
        
        do {
            print("[InviteMember] Inviting: \(trimmedEmail) to group: \(groupId)")
            try await appState.addMember(groupId: groupId, email: trimmedEmail)
            print("[InviteMember] Success!")
            dismiss()
        } catch {
            isInviting = false
            print("[InviteMember] Failed: \(error)")
            
            if let apiError = error as? APIError {
                switch apiError {
                case .serverError(404, _):
                    errorMessage = "No user found with email \(trimmedEmail). They need to sign up first."
                case .serverError(400, let message):
                    if message?.contains("already a member") == true {
                        errorMessage = "This user is already a member of the group."
                    } else {
                        errorMessage = message ?? "Cannot add member"
                    }
                case .serverError(409, _):
                    errorMessage = "This user is already a member of the group."
                case .unauthorized:
                    errorMessage = "Session expired. Please login again."
                case .serverError(403, _):
                    errorMessage = "Only group owners can invite members."
                case .validationError(let message):
                    errorMessage = message
                case .networkError:
                    errorMessage = "Cannot connect to server"
                default:
                    errorMessage = apiError.localizedDescription
                }
            } else {
                errorMessage = "Failed to invite member"
            }
            showError = true
        }
    }
}

struct AddExpenseSheet: View {
    let groupId: UUID
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var expenseDescription: String = ""
    @State private var expenseAmount: String = ""
    @State private var selectedCurrency: String = "USD"
    @State private var selectedPayerId: UUID?
    @State private var selectedParticipantIds: Set<UUID> = []
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    
    let currencies = ["USD", "EUR", "GBP", "JPY", "KRW", "CNY", "CAD", "AUD"]
    
    private var members: [Membership] {
        appState.membershipsByGroupId[groupId] ?? []
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Expense Details")) {
                    TextField("Description", text: $expenseDescription)
                        .textInputAutocapitalization(.sentences)
                        .disabled(isCreating)
                    
                    TextField("Amount", text: $expenseAmount)
                        .keyboardType(.decimalPad)
                        .disabled(isCreating)
                    
                    Picker("Currency", selection: $selectedCurrency) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency).tag(currency)
                        }
                    }
                    .disabled(isCreating)
                }
                
                // Paid By Section
                Section(header: Text("Paid By")) {
                    if members.isEmpty {
                        Text("Loading members...")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Paid by", selection: $selectedPayerId) {
                            ForEach(members) { member in
                                HStack {
                                    Text(member.displayName)
                                    if member.userId == appState.user?.id {
                                        Text("(You)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(Optional(member.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(isCreating)
                    }
                }
                
                // Split Among Section
                Section(header: Text("Split Among")) {
                    if members.isEmpty {
                        Text("Loading members...")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(members) { member in
                            Button {
                                if selectedParticipantIds.contains(member.id) {
                                    selectedParticipantIds.remove(member.id)
                                } else {
                                    selectedParticipantIds.insert(member.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedParticipantIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedParticipantIds.contains(member.id) ? .blue : .secondary)
                                    
                                    Text(member.displayName)
                                        .foregroundStyle(.primary)
                                    
                                    if member.userId == appState.user?.id {
                                        Text("(You)")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .disabled(isCreating)
                        }
                    }
                }
                
                Section {
                    Button {
                        Task { await createExpense() }
                    } label: {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text("Create Expense")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(expenseDescription.isEmpty || expenseAmount.isEmpty || selectedParticipantIds.isEmpty || isCreating)
                }
            }
            .navigationTitle("New Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .task {
                // Initialize defaults when sheet appears
                if let userMembership = appState.getUserMembership(groupId: groupId) {
                    selectedPayerId = userMembership.id
                }
                // Select all members by default
                selectedParticipantIds = Set(members.map { $0.id })
            }
        }
    }
    
    private func createExpense() async {
        let trimmedDescription = expenseDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedDescription.isEmpty else {
            errorMessage = "Description is required"
            showError = true
            return
        }
        
        guard let amountValue = Decimal(string: expenseAmount), amountValue > 0 else {
            errorMessage = "Amount must be greater than 0"
            showError = true
            return
        }
        
        guard let payerId = selectedPayerId else {
            errorMessage = "Please select who paid"
            showError = true
            return
        }
        
        guard !selectedParticipantIds.isEmpty else {
            errorMessage = "Please select at least one participant"
            showError = true
            return
        }
        
        isCreating = true
        
        do {
            print("[AddExpense] Creating expense: \(trimmedDescription) - \(amountValue) \(selectedCurrency)")
            print("[AddExpense] Paid by: \(payerId)")
            print("[AddExpense] Split among \(selectedParticipantIds.count) members")
            
            // Convert dollars to cents
            let amountCents = Int(NSDecimalNumber(decimal: amountValue * 100).intValue)
            
            // Get current date in ISO8601 format (YYYY-MM-DD)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone.current
            let todayString = dateFormatter.string(from: Date())
            
            let request = CreateExpenseRequest(
                title: trimmedDescription,
                amountCents: amountCents,
                currency: selectedCurrency,
                paidBy: payerId,
                expenseDate: todayString,
                splitAmong: Array(selectedParticipantIds)
            )
            
            try await appState.createExpense(groupId: groupId, request: request)
            
            print("[AddExpense] Success!")
            dismiss()
        } catch {
            isCreating = false
            print("[AddExpense] Failed: \(error)")
            
            if let apiError = error as? APIError {
                switch apiError {
                case .validationError(let message):
                    errorMessage = message
                case .serverError(let code, let message):
                    errorMessage = message ?? "Server error (\(code))"
                case .unauthorized:
                    errorMessage = "Session expired. Please login again."
                case .networkError:
                    errorMessage = "Cannot connect to server"
                default:
                    errorMessage = apiError.localizedDescription
                }
            } else {
                errorMessage = "Failed to create expense"
            }
            showError = true
        }
    }
}

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
                
                HStack {
                    Text("Members")
                    Spacer()
                    Text("Coming soon")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            
            // Expenses Section (Placeholder)
            Section(header: Text("Expenses")) {
                HStack {
                    Image(systemName: "dollarsign.circle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text("No expenses yet")
                            .foregroundStyle(.secondary)
                        Text("Tap + to add your first expense")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Balances Section (Placeholder)
            Section(header: Text("Balances")) {
                HStack {
                    Image(systemName: "chart.pie")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text("No balances to show")
                            .foregroundStyle(.secondary)
                        Text("Add expenses to see who owes whom")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // TODO: Add expense
                    print("[GroupDetail] Add expense tapped")
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
        }
    }
}

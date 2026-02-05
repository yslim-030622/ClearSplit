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
import PhotosUI

// MARK: - Models

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
}

struct User: Codable, Identifiable {
    let id: UUID
    let username: String
    let email: String
    let firstName: String
    let lastName: String
}

extension User {
    var displayName: String {
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        if !fullName.isEmpty {
            return fullName
        }
        return email.components(separatedBy: "@").first ?? username
    }
    
    var initials: String {
        let firstInitial = firstName.first.map(String.init) ?? ""
        let lastInitial = lastName.first.map(String.init) ?? ""
        let combined = (firstInitial + lastInitial).uppercased()
        if !combined.isEmpty {
            return combined
        }
        return username.prefix(2).uppercased()
    }
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
    let username: String?
    let email: String?
    
    init(username: String? = nil, email: String? = nil) {
        self.username = username
        self.email = email
    }
}

struct MemberPreviewResponse: Codable {
    let found: Bool
    let alreadyMember: Bool?
    let user: User?
    let membershipId: UUID?
    let role: String?
}

// MARK: - Shopping Models

struct ShoppingSession: Codable, Identifiable {
    let id: UUID
    let groupId: UUID
    let title: String
    let shoppingDate: String?
    let totalAmount: Double?
    let currency: String
    let paidByMembershipId: UUID
    let createdAt: Date
    let participants: [ShoppingSessionParticipant]
    let receipts: [ReceiptUpload]
    let items: [ShoppingItem]
    
    var totalCents: Int {
        // If totalAmount is set, use it; otherwise calculate from items
        if let total = totalAmount {
            return Int(total * 100)
        }
        return items.reduce(0) { $0 + $1.totalCents }
    }
    
    var displayTotal: String {
        formatCurrency(cents: totalCents, currency: currency)
    }
}

struct ShoppingSessionParticipant: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let membershipId: UUID
    let createdAt: Date
}

struct ReceiptUpload: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let storageKey: String
    let contentType: String
    let createdAt: Date
}

struct ReceiptDownloadURLResponse: Codable {
    let receiptUploadId: UUID
    let expiresInSeconds: Int
    let url: String
    
    // No CodingKeys needed - APIClient uses convertFromSnakeCase which automatically
    // converts receipt_upload_id -> receiptUploadId and expires_in_seconds -> expiresInSeconds
}

struct ShoppingItem: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let name: String
    let quantity: Int
    let unitPriceCents: Int?
    let totalCents: Int
    let createdAt: Date
    let splits: [ShoppingItemSplit]
    
    var displayTotal: String {
        let amount = Double(totalCents) / 100.0
        return String(format: "$%.2f", amount)
    }
}

struct ShoppingItemSplit: Codable, Identifiable {
    let id: UUID
    let itemId: UUID
    let membershipId: UUID
    let shareCents: Int
    
    var displayAmount: String {
        let amount = Double(shareCents) / 100.0
        return String(format: "$%.2f", amount)
    }
}

struct ShoppingSessionCreate: Codable {
    let title: String
    let shoppingDate: String?
    let totalAmount: Double?
    let paidBy: UUID
}

struct ShoppingItemCreate: Codable {
    let name: String
    let quantity: Int
    let unitPriceCents: Int?
    let totalCents: Int
}

struct ParticipantSetRequest: Codable {
    let participantMembershipIds: [UUID]
}

struct SharersSetRequest: Codable {
    let membershipIds: [UUID]
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
    @Published var shoppingSessionsByGroupId: [UUID: [ShoppingSession]] = [:]
    @Published var isLoadingShopping: Bool = false

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

    func signup(username: String, email: String, password: String, firstName: String, lastName: String) async throws {
        print("[AppState] Signup started for: \(username) (\(email))")
        isLoading = true
        defer { isLoading = false }
        
        struct SignupRequest: Encodable {
            let username: String
            let email: String
            let password: String
            let first_name: String
            let last_name: String
            
            enum CodingKeys: String, CodingKey {
                case username, email, password
                case first_name = "first_name"
                case last_name = "last_name"
            }
        }
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
            body: SignupRequest(
                username: username,
                email: email,
                password: password,
                first_name: firstName,
                last_name: lastName
            ),
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
    
    func login(identifier: String, password: String) async throws {
        print("[AppState] Login started for: \(identifier)")
        isLoading = true
        defer { isLoading = false }

        print("[AppState] Calling authService.login...")
        let tokens = try await authService.login(identifier: identifier, password: password)
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
    
    func addMemberToGroup(groupId: UUID, username: String? = nil, email: String? = nil) async throws -> Membership {
        let identifier = username ?? email ?? ""
        print("[AppState] Adding member \(identifier) to group: \(groupId)")
        let membership = try await apiClient.addGroupMember(groupId: groupId, username: username, email: email)
        
        // Reload members to update cache
        try await loadMembers(groupId: groupId)
        
        return membership
    }
    
    // MARK: - Shopping Sessions
    
    func loadShoppingSessions(groupId: UUID) async throws {
        print("[AppState] Loading shopping sessions for group: \(groupId)")
        isLoadingShopping = true
        defer { isLoadingShopping = false }
        
        let sessions = try await apiClient.listShoppingSessions(groupId: groupId)
        shoppingSessionsByGroupId[groupId] = sessions
        print("[AppState] Loaded \(sessions.count) shopping sessions")
    }
    
    func createShoppingSession(groupId: UUID, title: String, paidBy: UUID, shoppingDate: Date? = nil, totalAmount: Double? = nil) async throws -> ShoppingSession {
        print("[AppState] Creating shopping session: \(title)")
        
        // Convert Date to String in YYYY-MM-DD format if provided
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = shoppingDate.map { dateFormatter.string(from: $0) }
        
        let request = ShoppingSessionCreate(title: title, shoppingDate: dateString, totalAmount: totalAmount, paidBy: paidBy)
        let session = try await apiClient.createShoppingSession(groupId: groupId, request: request)
        
        // Update local cache
        var sessions = shoppingSessionsByGroupId[groupId] ?? []
        sessions.insert(session, at: 0)
        shoppingSessionsByGroupId[groupId] = sessions
        
        return session
    }
    
    func refreshShoppingSession(sessionId: UUID, groupId: UUID) async throws -> ShoppingSession {
        let session = try await apiClient.getShoppingSession(sessionId: sessionId)
        
        // Update in cache
        if var sessions = shoppingSessionsByGroupId[groupId] {
            if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[index] = session
                shoppingSessionsByGroupId[groupId] = sessions
            }
        }
        
        return session
    }
    
    func setSessionParticipants(sessionId: UUID, groupId: UUID, membershipIds: [UUID]) async throws -> ShoppingSession {
        let session = try await apiClient.setParticipants(sessionId: sessionId, membershipIds: membershipIds)
        
        // Update in cache
        if var sessions = shoppingSessionsByGroupId[groupId] {
            if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[index] = session
                shoppingSessionsByGroupId[groupId] = sessions
            }
        }
        
        return session
    }
    
    func createShoppingItem(sessionId: UUID, groupId: UUID, name: String, quantity: Int, totalCents: Int) async throws -> ShoppingItem {
        let request = ShoppingItemCreate(name: name, quantity: quantity, unitPriceCents: nil, totalCents: totalCents)
        let item = try await apiClient.createShoppingItem(sessionId: sessionId, request: request)
        
        // Refresh session to get updated items
        _ = try await refreshShoppingSession(sessionId: sessionId, groupId: groupId)
        
        return item
    }
    
    func setItemSharers(itemId: UUID, sessionId: UUID, groupId: UUID, membershipIds: [UUID]) async throws -> ShoppingItem {
        let item = try await apiClient.setItemSharers(itemId: itemId, membershipIds: membershipIds)
        
        // Refresh session to get updated splits
        _ = try await refreshShoppingSession(sessionId: sessionId, groupId: groupId)
        
        return item
    }
    
    func uploadReceipt(sessionId: UUID, groupId: UUID, imageData: Data, contentType: String = "image/jpeg") async throws -> ReceiptUpload {
        print("[AppState] Uploading receipt for session: \(sessionId)")
        let receipt = try await apiClient.uploadReceipt(sessionId: sessionId, imageData: imageData, contentType: contentType)
        
        // Refresh session to get updated receipts
        _ = try await refreshShoppingSession(sessionId: sessionId, groupId: groupId)
        
        return receipt
    }
    
    func getReceiptDownloadURL(receiptUploadId: UUID) async throws -> String {
        print("[AppState] Getting download URL for receipt: \(receiptUploadId)")
        let response = try await apiClient.getReceiptDownloadURL(receiptUploadId: receiptUploadId)
        return response.url
    }
    
    func previewMemberInvite(groupId: UUID, username: String? = nil, email: String? = nil) async throws -> MemberPreviewResponse {
        let identifier = username ?? email ?? ""
        print("[AppState] Previewing invite for: \(identifier)")
        return try await apiClient.previewMemberInvite(groupId: groupId, username: username, email: email)
    }
    
    func addMember(groupId: UUID, username: String? = nil, email: String? = nil) async throws {
        let identifier = username ?? email ?? ""
        print("[AppState] Adding member \(identifier) to group: \(groupId)")
        isLoading = true
        defer { isLoading = false }
        
        let newMembership = try await apiClient.addGroupMember(groupId: groupId, username: username, email: email)
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
        async let _ = loadExpenses(groupId: groupId)
        async let _ = loadBalances(groupId: groupId)
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
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

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
        NavigationStack {
            SwiftUI.Group {
                if appState.user != nil {
                    GroupsListView()
                        .environmentObject(appState)
                } else if appState.isLoading {
                    ProgressView("Loading…")
                } else {
                    LoginView()
                }
            }
            .task {
                await appState.bootstrap()
            }
        }
    }
}

// MARK: - Groups List View

struct GroupsListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showCreateGroup = false
    @State private var showLogoutAlert = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            Color(hex: "F9FAFB")
                .ignoresSafeArea()
            
            // Content
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("My Groups")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color(hex: "111827"))
                            .tracking(-0.5)
                        
                        Spacer()
                        
                        // Logout button (top right)
                        Button(action: { showLogoutAlert = true }) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Color(hex: "2563EB"))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Log out")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 47 + 8) // Safe area + spacing
                    
                    // Group Cards
                    if isLoading && appState.groups.isEmpty {
                        // Loading skeleton
                        VStack(spacing: 12) {
                            ForEach(0..<3) { _ in
                                GroupCardSkeleton()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    } else if appState.groups.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "person.3")
                                .font(.system(size: 64))
                                .foregroundColor(Color(hex: "D1D5DB"))
                            
                            Text("No groups yet")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Color(hex: "4B5563"))
                            
                            Text("Create a group to start splitting expenses")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(Color(hex: "6B7280"))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(appState.groups) { group in
                                GroupCardView(group: group)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 100) // Space for button
                    }
                }
            }
            .refreshable {
                await refreshGroups()
            }
            
            // Bottom Button
            Button(action: { showCreateGroup = true }) {
                Text("Create New Group")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: "2563EB"))
                    .cornerRadius(12)
                    .shadow(color: Color(hex: "2563EB").opacity(0.2), radius: 8, y: 2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 34 + 16) // Safe area + margin
            .accessibilityLabel("Create new group")
        }
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupView()
        }
        .alert("Log Out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                Task { await appState.logout() }
            }
        } message: {
            Text("Are you sure you want to log out?")
        }
        .task {
            await refreshGroups()
        }
        .navigationDestination(for: Group.self) { group in
            GroupDetailView(group: group)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("Retry") { Task { await refreshGroups() } }
            Button("Cancel", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private func refreshGroups() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await appState.loadGroups()
        } catch {
            errorMessage = "Failed to load groups: \(error.localizedDescription)"
        }
    }
}

struct GroupCardView: View {
    let group: Group
    @EnvironmentObject private var appState: AppState
    @State private var isPressed = false
    
    private var memberCount: Int {
        appState.membershipsByGroupId[group.id]?.count ?? 0
    }
    
    private var userBalance: Decimal {
        // Calculate balance from settlements if available
        guard let settlements = appState.settlementsByGroupId[group.id] else {
            return 0
        }
        // Sum up the user's balance from settlements
        // For now, return 0 (settled) - this would need proper calculation
        return 0
    }
    
    private var isSettled: Bool {
        userBalance == 0
    }
    
    var body: some View {
        NavigationLink(value: group) {
            HStack(spacing: 0) {
                // Left: Group info
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: "111827"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "6B7280"))
                        
                        Text("\(memberCount) \(memberCount == 1 ? "member" : "members")")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "4B5563"))
                    }
                }
                
                Spacer()
                
                // Right: Balance
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if !isSettled {
                            Text("Your balance")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color(hex: "6B7280"))
                        }
                        
                        if isSettled {
                            Text("All settled up")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color(hex: "6B7280"))
                        } else {
                            Text(balanceText)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(balanceColor)
                        }
                    }
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "9CA3AF"))
                }
            }
            .padding(16)
            .frame(height: 72)
            .background(isPressed ? Color(hex: "F9FAFB") : .white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
            )
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
            .scaleEffect(isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
    
    private var balanceText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = group.currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        
        let amount = abs(userBalance)
        let formatted = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$0.00"
        
        return userBalance > 0 ? "+\(formatted)" : formatted
    }
    
    private var balanceColor: Color {
        userBalance > 0 ? Color(hex: "16A34A") : Color(hex: "DC2626")
    }
}

struct GroupCardSkeleton: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 120, height: 17)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 80, height: 14)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 70, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 60, height: 17)
            }
        }
        .padding(16)
        .frame(height: 72)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
        )
        .cornerRadius(12)
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
        
        // Configure decoder - use ISO8601 with fractional seconds
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
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
    
    func previewMemberInvite(groupId: UUID, username: String? = nil, email: String? = nil) async throws -> MemberPreviewResponse {
        let identifier = username ?? email ?? ""
        print("[APIClient] Previewing invite for \(identifier) in group: \(groupId)")
        
        let preview: MemberPreviewResponse = try await request(
            "/groups/\(groupId.uuidString)/members/preview",
            method: "POST",
            body: MemberPreviewRequest(username: username, email: email),
            requiresAuth: true
        )
        
        print("[APIClient] Preview result: found=\(preview.found), alreadyMember=\(preview.alreadyMember ?? false)")
        return preview
    }
    
    func addGroupMember(groupId: UUID, username: String? = nil, email: String? = nil) async throws -> Membership {
        let identifier = username ?? email ?? ""
        print("[APIClient] Adding member \(identifier) to group: \(groupId)")
        
        struct AddMemberRequest: Encodable {
            let username: String?
            let email: String?
            let role: String = "member"
        }
        
        let membership: Membership = try await request(
            "/groups/\(groupId.uuidString)/members",
            method: "POST",
            body: AddMemberRequest(username: username, email: email),
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
    
    // MARK: - Shopping Sessions API
    
    func listShoppingSessions(groupId: UUID) async throws -> [ShoppingSession] {
        print("[APIClient] Fetching shopping sessions for group: \(groupId)")
        return try await self.request(
            "/groups/\(groupId.uuidString)/shopping-sessions",
            method: "GET",
            requiresAuth: true
        )
    }
    
    func createShoppingSession(groupId: UUID, request: ShoppingSessionCreate) async throws -> ShoppingSession {
        print("[APIClient] Creating shopping session: \(request.title)")
        return try await self.request(
            "/groups/\(groupId.uuidString)/shopping-sessions",
            method: "POST",
            body: request,
            requiresAuth: true
        )
    }
    
    func getShoppingSession(sessionId: UUID) async throws -> ShoppingSession {
        print("[APIClient] Fetching shopping session: \(sessionId)")
        return try await self.request(
            "/shopping-sessions/\(sessionId.uuidString)",
            method: "GET",
            requiresAuth: true
        )
    }
    
    func setParticipants(sessionId: UUID, membershipIds: [UUID]) async throws -> ShoppingSession {
        print("[APIClient] Setting participants for session: \(sessionId)")
        let request = ParticipantSetRequest(participantMembershipIds: membershipIds)
        return try await self.request(
            "/shopping-sessions/\(sessionId.uuidString)/participants",
            method: "PUT",
            body: request,
            requiresAuth: true
        )
    }
    
    func createShoppingItem(sessionId: UUID, request: ShoppingItemCreate) async throws -> ShoppingItem {
        print("[APIClient] Creating item: \(request.name)")
        return try await self.request(
            "/shopping-sessions/\(sessionId.uuidString)/items",
            method: "POST",
            body: request,
            requiresAuth: true
        )
    }
    
    func setItemSharers(itemId: UUID, membershipIds: [UUID]) async throws -> ShoppingItem {
        print("[APIClient] Setting sharers for item: \(itemId)")
        let request = SharersSetRequest(membershipIds: membershipIds)
        return try await self.request(
            "/items/\(itemId.uuidString)/sharers",
            method: "PUT",
            body: request,
            requiresAuth: true
        )
    }
    
    func uploadReceipt(sessionId: UUID, imageData: Data, contentType: String) async throws -> ReceiptUpload {
        print("[APIClient] Uploading receipt for session: \(sessionId)")
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = createMultipartBody(boundary: boundary, imageData: imageData, contentType: contentType)
        
        guard let url = URL(string: "/shopping-sessions/\(sessionId.uuidString)/receipt", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        if let tokens = tokenProvider() {
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError(-1, "Invalid response")
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        return try decoder.decode(ReceiptUpload.self, from: data)
    }
    
    func getReceiptDownloadURL(receiptUploadId: UUID) async throws -> ReceiptDownloadURLResponse {
        print("[APIClient] Fetching download URL for receipt: \(receiptUploadId)")
        return try await self.request(
            "/receipts/\(receiptUploadId.uuidString)/download-url",
            method: "GET",
            requiresAuth: true
        )
    }
    
    private func createMultipartBody(boundary: String, imageData: Data, contentType: String) -> Data {
        var body = Data()
        
        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"receipt.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
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

    func login(identifier: String, password: String) async throws -> AuthTokens {
        struct LoginRequest: Encodable { let identifier: String; let password: String }
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
            body: LoginRequest(identifier: identifier, password: password),
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

// MARK: - Helpers

func formatCurrency(cents: Int, currency: String) -> String {
    let amount = Double(cents) / 100.0
    return String(format: "$%.2f", amount)
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

// MARK: - Design System Colors
extension Color {
    static let blue600 = Color(hex: "2563EB")
    static let blue700 = Color(hex: "1D4ED8")
    static let blue500 = Color(hex: "3B82F6")
    static let blue50 = Color(hex: "EFF6FF")
    static let blue200 = Color(hex: "BFDBFE")
    static let blue900 = Color(hex: "1E3A8A")
    static let green600 = Color(hex: "16A34A")
    static let gray800 = Color(hex: "1F2937")
    static let gray900 = Color(hex: "111827")
    static let gray700 = Color(hex: "374151")
    static let gray600 = Color(hex: "4B5563")
    static let gray500 = Color(hex: "6B7280")
    static let gray400 = Color(hex: "9CA3AF")
    static let gray300 = Color(hex: "D1D5DB")
    static let gray200 = Color(hex: "E5E7EB")
    static let gray100 = Color(hex: "F3F4F6")
    static let gray50 = Color(hex: "F9FAFB")
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Views

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @State private var showSignUp = false
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [Color.blue50, Color.gray50],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Logo Section
                    VStack(spacing: 12) {
                        // Logo Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue600)
                                .frame(width: 64, height: 64)
                                .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 4)
                            
                            Image(systemName: "doc.text")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel("ClearSplit logo")
                        
                        // App Name
                        Text("ClearSplit")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.gray900)
                        
                        // Tagline
                        Text("\"clearly split with your friends\"")
                            .font(.system(size: 16, weight: .regular))
                            .italic()
                            .foregroundColor(.gray600)
                    }
                    
                    Spacer()
                        .frame(height: 32)
                    
                    // Form Card
                    VStack(spacing: 20) {
                        // Username or Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username or Email")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray700)
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        focusedField == .email ? Color.blue500 : Color.gray300,
                                        lineWidth: focusedField == .email ? 2 : 1
                                    )
                                
                                if focusedField == .email {
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(Color.blue500.opacity(0.5), lineWidth: 3)
                                        .padding(-3)
                                }
                                
                                TextField("username or email", text: $email)
                                    .textContentType(.username)
                                    .keyboardType(.default)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.gray900)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .focused($focusedField, equals: .email)
                                    .submitLabel(.next)
                                    .onSubmit {
                                        focusedField = .password
                                    }
                            }
                            .frame(height: 48)
                        }
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray700)
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        focusedField == .password ? Color.blue500 : Color.gray300,
                                        lineWidth: focusedField == .password ? 2 : 1
                                    )
                                
                                if focusedField == .password {
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(Color.blue500.opacity(0.5), lineWidth: 3)
                                        .padding(-3)
                                }
                                
                                SecureField("••••••••", text: $password)
                                    .textContentType(.password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.gray900)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        if !email.isEmpty && !password.isEmpty {
                                            Task { await submit() }
                                        }
                                    }
                            }
                            .frame(height: 48)
                        }
                        
                        // Log In Button
                    Button {
                        Task { await submit() }
                    } label: {
                            HStack {
                        if isSubmitting {
                            ProgressView()
                                        .tint(.white)
                                }
                                Text("Log In")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.blue600)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isSubmitting || email.isEmpty || password.isEmpty)
                        .opacity((isSubmitting || email.isEmpty || password.isEmpty) ? 0.5 : 1.0)
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(24)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray200, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
                    
                    Spacer()
                        .frame(height: 32)
                    
                    // Sign Up Section
                    VStack(spacing: 12) {
                        Text("Don't have an account?")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.gray600)
                        
                        Button {
                            showSignUp = true
                        } label: {
                            Text("Create Account")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.gray900)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray200, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isSubmitting)
                        .buttonStyle(ScaleButtonStyle())
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 384)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSignUp) {
                SignUpView()
            }
            .alert("Error", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func submit() async {
        print("[LoginView] Submit called with identifier: \(email)")
        guard !email.isEmpty, !password.isEmpty else {
            print("[LoginView] Identifier or password is empty")
            return
        }
        isSubmitting = true
        do {
            print("[LoginView] Calling appState.login...")
            try await appState.login(identifier: email, password: password)
            print("[LoginView] Login succeeded!")
        } catch {
            print("[LoginView] Login failed: \(error)")
            // Note: APIClient throws APIError with cases: server(status:message:), network(Error), decoding, unauthorized
            // But this file also defines APIError with different cases. The local enum shadows the APIClient one.
            // For now, handle errors generically
            if let apiError = error as? APIError {
                switch apiError {
                case .serverError(_, let message):
                    alertMessage = message ?? "Invalid username/email or password."
                case .unauthorized:
                    alertMessage = "Invalid username/email or password."
                case .networkError(_):
                    alertMessage = "Network error. Please check your connection."
                case .decodingError(_):
                    alertMessage = "Invalid response from server. Please try again."
                default:
                    alertMessage = apiError.errorDescription ?? error.localizedDescription
                }
            } else {
                // If it's not our APIError, it might be APIClient's APIError - handle generically
                alertMessage = error.localizedDescription
            }
        }
        isSubmitting = false
    }
}

// MARK: - Sign Up Sub-Views
struct SignUpLogoSection: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.blue600)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.blue600.opacity(0.15), radius: 8, y: 2)
                
                Image(systemName: "tablecells")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
            }
            .accessibilityLabel("ClearSplit app icon")
            
            Text("Create Account")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.gray900)
                .tracking(-0.5)
            
            Text("Join your roommates on ClearSplit")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray600)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }
}

struct SignUpFormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let focusedField: SignUpView.Field?
    let field: SignUpView.Field
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType
    let autocapitalization: TextInputAutocapitalization
    let enableAutocorrection: Bool
    let focusBinding: FocusState<SignUpView.Field?>.Binding
    let onSubmit: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Font.system(size: 14, weight: .medium))
                .foregroundColor(Color.gray700)
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(focusedField == field ? Color.white : Color.gray50)
                
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        focusedField == field ? Color.blue600 : Color.clear,
                        lineWidth: focusedField == field ? 2 : 0
                    )
                
                if focusedField == field {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(Color.blue600.opacity(0.1), lineWidth: 4)
                          .padding(-4)
                  }
                  
                  if enableAutocorrection {
                    TextField(placeholder, text: $text)
                        .textContentType(textContentType)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(autocapitalization)
                        .font(Font.system(size: 16, weight: .regular))
                        .foregroundColor(Color.gray900)
                        .padding(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                        .focused(focusBinding, equals: field)
                        .submitLabel(field == .password ? SubmitLabel.done : SubmitLabel.next)
                        .onSubmit {
                            onSubmit?()
                        }
                } else {
                    TextField(placeholder, text: $text)
                        .textContentType(textContentType)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled()
                        .font(Font.system(size: 16, weight: .regular))
                        .foregroundColor(Color.gray900)
                        .padding(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                        .focused(focusBinding, equals: field)
                        .submitLabel(field == .password ? SubmitLabel.done : SubmitLabel.next)
                        .onSubmit {
                            onSubmit?()
                        }
                }
            }
            .frame(height: 48)
        }
    }
}

struct SignUpPasswordField: View {
    @Binding var password: String
    @Binding var isPasswordVisible: Bool
    let focusedField: SignUpView.Field?
    let isFormValid: Bool
    let focusBinding: FocusState<SignUpView.Field?>.Binding
    let onSubmit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Password")
                .font(Font.system(size: 14, weight: .medium))
                .foregroundColor(Color.gray700)
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(focusedField == .password ? Color.white : Color.gray50)
                
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        focusedField == .password ? Color.blue600 : Color.clear,
                        lineWidth: focusedField == .password ? 2 : 0
                    )
                
                if focusedField == .password {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(Color.blue600.opacity(0.1), lineWidth: 4)
                        .padding(-4)
                }
                
                HStack {
                    if isPasswordVisible {
                        TextField("••••••••", text: $password)
                            .textContentType(.newPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(Font.system(size: 16, weight: .regular))
                            .foregroundColor(Color.gray900)
                            .focused(focusBinding, equals: .password)
                            .submitLabel(SubmitLabel.done)
                            .onSubmit {
                                if isFormValid {
                                    onSubmit()
                                }
                            }
                    } else {
                        SecureField("••••••••", text: $password)
                            .textContentType(.newPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(Font.system(size: 16, weight: .regular))
                            .foregroundColor(Color.gray900)
                            .focused(focusBinding, equals: .password)
                            .submitLabel(SubmitLabel.done)
                            .onSubmit {
                                if isFormValid {
                                    onSubmit()
                                }
                            }
                    }
                    
                    Button(action: { isPasswordVisible.toggle() }) {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .font(Font.system(size: 20))
                            .foregroundColor(Color.gray500)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                }
                .padding(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
            }
            .frame(height: 48)
        }
    }
}

struct SignUpView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var username: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @FocusState private var focusedField: Field?
    
    enum Field {
        case username, firstName, lastName, email, password
    }
    
    private var isFormValid: Bool {
        !username.isEmpty &&
        isValidUsername(username) &&
        !firstName.isEmpty &&
        !lastName.isEmpty &&
        !email.isEmpty &&
        isValidEmail(email) &&
        !password.isEmpty &&
        password.count >= 8
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 40)
                
                SignUpLogoSection()
                
                Spacer()
                    .frame(height: 36)
                
                // Form Card
                VStack(alignment: .leading, spacing: 20) {
                    SignUpFormField(
                        label: "Username",
                        placeholder: "alex123",
                        text: $username,
                        focusedField: focusedField,
                        field: .username,
                        keyboardType: .default,
                        textContentType: .username,
                        autocapitalization: .never,
                        enableAutocorrection: false,
                        focusBinding: $focusedField,
                        onSubmit: { focusedField = .firstName }
                    )
                    
                    SignUpFormField(
                        label: "First Name",
                        placeholder: "Alex",
                        text: $firstName,
                        focusedField: focusedField,
                        field: .firstName,
                        keyboardType: .default,
                        textContentType: .givenName,
                        autocapitalization: .words,
                        enableAutocorrection: true,
                        focusBinding: $focusedField,
                        onSubmit: { focusedField = .lastName }
                    )
                    
                    SignUpFormField(
                        label: "Last Name",
                        placeholder: "Smith",
                        text: $lastName,
                        focusedField: focusedField,
                        field: .lastName,
                        keyboardType: .default,
                        textContentType: .familyName,
                        autocapitalization: .words,
                        enableAutocorrection: true,
                        focusBinding: $focusedField,
                        onSubmit: { focusedField = .email }
                    )
                    
                    SignUpFormField(
                        label: "Email",
                        placeholder: "you@example.com",
                        text: $email,
                        focusedField: focusedField,
                        field: .email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never,
                        enableAutocorrection: false,
                        focusBinding: $focusedField,
                        onSubmit: { focusedField = .password }
                    )
                    
                    SignUpPasswordField(
                        password: $password,
                        isPasswordVisible: $isPasswordVisible,
                        focusedField: focusedField,
                        isFormValid: isFormValid,
                        focusBinding: $focusedField,
                        onSubmit: { Task { await signUp() } }
                    )
                    
                    // Create Account Button
                    Button(action: { Task { await signUp() } }) {
                        HStack {
                    if isSubmitting {
                        ProgressView()
                                    .tint(.white)
                    } else {
                                Text("Create Account")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                            .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(isFormValid ? Color.blue600 : Color.gray300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(
                            color: isFormValid ? Color.blue600.opacity(0.2) : .clear,
                            radius: 4, y: 2
                        )
                    }
                    .disabled(isSubmitting || !isFormValid)
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(24)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .background(Color(hex: "F0F4F8"))
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .regular))
                        Text("Back")
                            .font(.system(size: 16, weight: .regular))
                    }
                    .foregroundColor(.gray700)
                    .frame(width: 70, height: 44)
                }
                .accessibilityLabel("Back to login")
            }
        }
        .alert("Error", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }
    
    private func signUp() async {
        print("[SignUpView] Sign up called with email: \(email)")
        guard isFormValid else {
            print("[SignUpView] Validation failed")
            return
        }
        
        isSubmitting = true
        do {
            print("[SignUpView] Calling appState.signup...")
            try await appState.signup(
                username: username,
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName
            )
            print("[SignUpView] Sign up succeeded!")
            // No need to dismiss - the user is now authenticated and will see GroupsListView
        } catch {
            print("[SignUpView] Sign up failed: \(error)")
            // Note: APIClient throws APIError with cases: server(status:message:), network(Error), decoding, unauthorized
            // But this file also defines APIError with different cases. The local enum shadows the APIClient one.
            if let apiError = error as? APIError {
                switch apiError {
                case .serverError(_, let message):
                    alertMessage = message ?? "Server error. Please try again."
                case .unauthorized:
                    alertMessage = "Invalid credentials. Please check your information."
                case .networkError(_):
                    alertMessage = "Network error. Please check your connection."
                case .decodingError(_):
                    alertMessage = "Invalid response from server. Please try again."
                default:
                    alertMessage = apiError.errorDescription ?? error.localizedDescription
                }
            } else {
                alertMessage = error.localizedDescription
            }
        }
        isSubmitting = false
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func isValidUsername(_ username: String) -> Bool {
        // Username: 3-30 characters, alphanumeric, underscore, or hyphen only
        let usernameRegex = "^[a-zA-Z0-9_-]{3,30}$"
        let usernamePredicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        return usernamePredicate.evaluate(with: username)
    }
}

// GroupsListView has been moved to Sources/ClearSplit/Views/GroupsListView.swift
// This duplicate definition has been removed to avoid conflicts

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
    
    @State private var isShowingHelp = false
    @State private var isAddMemberDialogOpen = false
    @State private var memberToRemove: Membership?
    @State private var isRemoveDialogOpen = false
    
    // MARK: - Derived Data
    
    private var members: [Membership] {
        appState.membershipsByGroupId[group.id] ?? []
    }
    
    private var shoppingSessions: [ShoppingSession] {
        appState.shoppingSessionsByGroupId[group.id] ?? []
    }
    
    private var totalSpentCents: Int {
        shoppingSessions.reduce(0) { $0 + $1.totalCents }
    }
    
    private var totalSpentDisplay: String {
        formatCurrency(cents: totalSpentCents, currency: group.currency)
    }
    
    private var currentUserId: UUID? {
        appState.user?.id
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.gray50
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Total Spent hero card
                    TotalSpentCard(
                        amountText: totalSpentDisplay,
                        subtitle: shoppingSessions.isEmpty
                            ? "No expenses yet"
                            : "Across all shopping trips"
                    )
                    .padding(.top, 16)
                    
                    // Members card
                    MembersCard(
                        title: "Members",
                        members: members,
                        currentUserId: currentUserId,
                        groupName: group.name,
                        onAddMember: { isAddMemberDialogOpen = true },
                        onRemoveMember: { member in
                            memberToRemove = member
                            isRemoveDialogOpen = true
                        }
                    )
                    
                    // Navigation cards
                    VStack(spacing: 16) {
                if let membershipId = group.userMembershipId {
                            NavigationCard(
                                iconName: "list.bullet.rectangle",
                                iconBackground: Color.blue50,
                                iconColor: Color.blue600,
                                title: "Shopping Sessions",
                                subtitle: "View and manage grocery trips"
                            ) {
                                ShoppingSessionsListView(
                                    appState: appState,
                                    groupId: group.id,
                                    paidByMembershipId: membershipId
                                )
                            }
                        } else {
                            // Disabled card when membership is missing
                            NavigationCardContent(
                                iconName: "list.bullet.rectangle",
                                iconBackground: Color.gray100,
                                iconColor: Color.gray400,
                                title: "Shopping Sessions",
                                subtitle: "Unavailable for this group"
                            )
                            .opacity(0.6)
                        }
                        
                        NavigationLink {
                            // TODO: Replace placeholder with full balances & settlement screen
                            Text("Balances & Settlement")
                                .font(.title2)
                                    .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.gray50)
                    } label: {
                            NavigationCardContent(
                                iconName: "dollarsign.circle",
                                iconBackground: Color.green.opacity(0.1),
                                iconColor: Color.green600,
                                title: "Balances & Settlement",
                                subtitle: "See who owes what"
                            )
                        }
                    }
                    
                    Spacer(minLength: 34)
                }
                .padding(.horizontal, 16)
            }
            
            // Floating help button
            Button {
                isShowingHelp = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.gray800)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.trailing, 20)
            .padding(.bottom, 54)
        }
        .navigationTitle(group.name.isEmpty ? "Unnamed Group" : group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // TODO: Implement group settings screen
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color.gray600)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .task {
            await refreshData()
        }
        .refreshable {
            await refreshData()
        }
        .sheet(isPresented: $isShowingHelp) {
            GroupHelpSheet()
        }
        .sheet(isPresented: $isAddMemberDialogOpen) {
            AddMemberDialog(
                groupName: group.name,
                groupId: group.id,
                members: members,
                appState: appState,
                onDismiss: {
                    isAddMemberDialogOpen = false
                    Task {
                        await refreshData()
                    }
                }
            )
        }
        .alert("Remove Member?", isPresented: $isRemoveDialogOpen) {
            Button("Cancel", role: .cancel) {
                memberToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let member = memberToRemove {
                    Task {
                        // TODO: Implement remove member API call
                        // For now, just refresh
                        await refreshData()
                        memberToRemove = nil
                    }
                }
            }
        } message: {
            if let member = memberToRemove {
                let name = member.user?.firstName ?? member.displayName
                Text("Are you sure you want to remove \(name) from \(group.name)? This action cannot be undone.")
            }
        }
    }

    private func refreshData() async {
        async let membersTask = try? appState.loadMembers(groupId: group.id)
        async let sessionsTask = try? appState.loadShoppingSessions(groupId: group.id)
        async let balancesTask = try? appState.loadBalances(groupId: group.id)
        _ = await (membersTask, sessionsTask, balancesTask)
    }
    
    // MARK: - Subviews
    
    private struct TotalSpentCard: View {
        let amountText: String
        let subtitle: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Spent")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.9))
                
                Text(amountText)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(-1)
                
                Text(subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.8))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(Color.blue600)
            .cornerRadius(20)
            .shadow(color: Color.blue600.opacity(0.25), radius: 12, x: 0, y: 4)
        }
    }
    
    private struct MembersCard: View {
        let title: String
        let members: [Membership]
        let currentUserId: UUID?
        let groupName: String
        let onAddMember: () -> Void
        let onRemoveMember: (Membership) -> Void
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Header with Add button
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(Color(hex: "4B5563"))
                        Text("\(title) (\(members.count))")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Color(hex: "111827"))
                            .tracking(-0.3)
                    }
                    
                    Spacer()
                    
                    Button(action: onAddMember) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16, weight: .medium))
                            Text("Add")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "2563EB"))
                        .cornerRadius(8)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.bottom, 16)
                
                // Member list
                if members.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No members yet")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color(hex: "4B5563"))
                        Text("Invite your roommates to start splitting expenses.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "6B7280"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                } else {
                    VStack(spacing: 12) {
                        ForEach(members) { member in
                            MemberRow(
                                member: member,
                                isCurrentUser: member.userId == currentUserId,
                                onRemove: { onRemoveMember(member) }
                            )
                        }
                    }
                    .padding(.top, 16)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
            )
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
    
    private struct MemberRow: View {
        let member: Membership
        let isCurrentUser: Bool
        let onRemove: () -> Void
        @State private var isHovered = false
        
        private var displayName: String {
            if let user = member.user {
                let fullName = "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
                if !fullName.isEmpty {
                    return fullName
                }
                return user.email
            }
            return member.displayName
        }
        
        private var email: String? {
            member.user?.email
        }
        
        private var initials: String {
            if let user = member.user {
                let firstInitial = user.firstName.first.map(String.init) ?? ""
                let lastInitial = user.lastName.first.map(String.init) ?? ""
                let combined = (firstInitial + lastInitial)
                if !combined.isEmpty {
                    return combined.uppercased()
                }
            }
            return String(displayName.prefix(1)).uppercased()
        }
        
        private var avatarColor: (start: Color, end: Color) {
            let colors: [(Color, Color)] = [
                (Color(hex: "60A5FA"), Color(hex: "2563EB")), // Blue
                (Color(hex: "C084FC"), Color(hex: "9333EA")), // Purple
                (Color(hex: "4ADE80"), Color(hex: "16A34A")), // Green
                (Color(hex: "FB923C"), Color(hex: "EA580C")), // Orange
                (Color(hex: "F472B6"), Color(hex: "DB2777")), // Pink
                (Color(hex: "818CF8"), Color(hex: "4F46E5"))  // Indigo
            ]
            // Use member ID to consistently assign colors
            let index = abs(member.id.hashValue) % colors.count
            return colors[index]
        }
        
        var body: some View {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [avatarColor.start, avatarColor.end],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Text(initials)
                        .font(.system(size: initials.count > 1 ? 14 : 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Content area
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(isCurrentUser ? "You" : displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(hex: "111827"))
                            .lineLimit(1)
                        
                        if isCurrentUser {
                            Text("You")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "1D4ED8"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(hex: "DBEAFE"))
                                .cornerRadius(8)
                        }
                    }
                    
                    if let email = email {
                        Text(email)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "6B7280"))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Remove button (only for non-current users)
                if !isCurrentUser {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isHovered ? Color(hex: "DC2626") : Color(hex: "9CA3AF"))
                            .frame(width: 28, height: 28)
                            .background(isHovered ? Color(hex: "FEF2F2") : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .opacity(isHovered ? 1.0 : 0.6)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
                }
            }
            .frame(height: 56)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
    
    private struct AddMemberDialog: View {
        let groupName: String
        let groupId: UUID
        let members: [Membership]
        @ObservedObject var appState: AppState
        let onDismiss: () -> Void
        
        @State private var searchUserId = ""
        @State private var searchState: SearchState = .idle
        @State private var foundUser: User?
        @State private var errorMessage: String?
        
        @FocusState private var isInputFocused: Bool
        
        enum SearchState {
            case idle
            case searching
            case notFound
            case alreadyMember
            case found
        }
        
        private var canSearch: Bool {
            !searchUserId.trimmingCharacters(in: .whitespaces).isEmpty && searchState != .searching
        }
        
        private var canAdd: Bool {
            searchState == .found && foundUser != nil
        }
        
        var body: some View {
            ZStack {
                // Backdrop
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        resetDialog()
                    }
                
                // Dialog
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Section 1: Header
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Add Member")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color(hex: "111827"))
                                    .tracking(-0.4)
                                
                                Text("Search for a user by their ID to add them to \(groupName).")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color(hex: "4B5563"))
                                    .lineSpacing(4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 16)
                            
                            // Section 2: Search Input Area
                            VStack(alignment: .leading, spacing: 8) {
                                Text("User ID")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color(hex: "111827"))
                                
                                HStack(spacing: 8) {
                                    TextField("", text: $searchUserId)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(Color(hex: "111827"))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isInputFocused ? Color(hex: "2563EB") : Color(hex: "D1D5DB"), lineWidth: isInputFocused ? 2 : 1)
                                        )
                                        .disabled(searchState == .searching)
                                        .focused($isInputFocused)
                                        .onChange(of: searchUserId) { _ in
                                            if searchState != .idle {
                                                searchState = .idle
                                                foundUser = nil
                                            }
                                        }
                                        .onSubmit {
                                            if canSearch {
                                                handleSearchUser()
                                            }
                                        }
                                    
                                    Button(action: handleSearchUser) {
                                        HStack(spacing: 8) {
                                            if searchState == .searching {
                                                ProgressView()
                                                    .tint(.white)
                                                    .scaleEffect(0.8)
                                            } else {
                                                Image(systemName: "magnifyingglass")
                                                    .font(.system(size: 16, weight: .medium))
                                            }
                                            Text(searchState == .searching ? "Searching" : "Search")
                                                .font(.system(size: 14, weight: .medium))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .frame(height: 40)
                                        .background(canSearch ? Color(hex: "2563EB") : Color(hex: "D1D5DB"))
                                        .cornerRadius(8)
                                    }
                                    .disabled(!canSearch)
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                            .padding(.vertical, 16)
                            
                            // Section 3: Search Results Area
                            if searchState != .idle {
                                VStack(spacing: 0) {
                                    switch searchState {
                                    case .notFound:
                                        NotFoundResultCard(searchUserId: searchUserId)
                                    case .alreadyMember:
                                        if let user = foundUser {
                                            AlreadyMemberResultCard(user: user)
                                        }
                                    case .found:
                                        if let user = foundUser {
                                            FoundResultCard(user: user)
                                        }
                                    case .searching, .idle:
                                        EmptyView()
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(24)
                    }
                    
                    // Section 4: Dialog Footer
                    VStack(spacing: 0) {
                        Divider()
                            .padding(.top, 16)
                        
                        HStack(spacing: 8) {
                            Button(action: resetDialog) {
                                Text("Cancel")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color(hex: "374151"))
                                    .padding(.horizontal, 16)
                                    .frame(height: 40)
                                    .background(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(hex: "D1D5DB"), lineWidth: 1)
                                    )
                                    .cornerRadius(8)
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            Button(action: handleAddFoundUser) {
                                Text("Add Member")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .frame(height: 40)
                                    .background(canAdd ? Color(hex: "2563EB") : Color(hex: "D1D5DB"))
                                    .cornerRadius(8)
                            }
                            .disabled(!canAdd)
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                }
                .frame(maxWidth: 500)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
                .padding(.horizontal, 16)
            }
            .onAppear {
                isInputFocused = true
            }
        }
        
        private func handleSearchUser() {
            let trimmedId = searchUserId.trimmingCharacters(in: .whitespaces)
            guard !trimmedId.isEmpty else { return }
            
            searchState = .searching
            foundUser = nil
            errorMessage = nil
            
            Task {
                do {
                    let preview = try await appState.previewMemberInvite(groupId: groupId, username: trimmedId)
                    
                    await MainActor.run {
                        if !preview.found {
                            searchState = .notFound
                            foundUser = nil
                        } else if preview.alreadyMember == true {
                            searchState = .alreadyMember
                            foundUser = preview.user
                        } else if let user = preview.user {
                            searchState = .found
                            foundUser = user
                        } else {
                            searchState = .notFound
                            foundUser = nil
                        }
                    }
                } catch {
                    await MainActor.run {
                        searchState = .notFound
                        foundUser = nil
                        if let apiError = error as? APIError {
                            switch apiError {
                            case .serverError(_, let message):
                                errorMessage = message ?? "Failed to search for user"
                            default:
                                errorMessage = "Failed to search for user"
                            }
                        } else {
                            errorMessage = "Failed to search for user"
                        }
                    }
                }
            }
        }
        
        private func handleAddFoundUser() {
            guard let user = foundUser else { return }
            
            Task {
                do {
                    _ = try await appState.addMemberToGroup(groupId: groupId, username: user.username)
                    await MainActor.run {
                        resetDialog()
                        onDismiss()
                    }
                } catch {
                    await MainActor.run {
                        if let apiError = error as? APIError {
                            switch apiError {
                            case .serverError(_, let message):
                                errorMessage = message ?? "Failed to add member"
                            default:
                                errorMessage = "Failed to add member"
                            }
                        } else {
                            errorMessage = "Failed to add member"
                        }
                    }
                }
            }
        }
        
        private func resetDialog() {
            searchUserId = ""
            searchState = .idle
            foundUser = nil
            errorMessage = nil
        }
    }
    
    // MARK: - Result Cards
    
    private struct NotFoundResultCard: View {
        let searchUserId: String
        
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(hex: "DC2626"))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("User Not Found")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "7F1D1D"))
                    
                    Text("No user exists with ID \"\(searchUserId)\". Please check the ID and try again.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(hex: "B91C1C"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(hex: "FEF2F2"))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "FECACA"), lineWidth: 1)
            )
            .cornerRadius(12)
        }
    }
    
    private struct AlreadyMemberResultCard: View {
        let user: User
        
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(hex: "D97706"))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Already a Member")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "78350F"))
                    
                    Text("\(user.displayName) (\(user.email)) is already a member of this group.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(hex: "B45309"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(hex: "FFFBEB"))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "FDE68A"), lineWidth: 1)
            )
            .cornerRadius(12)
        }
    }
    
    private struct FoundResultCard: View {
        let user: User
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(hex: "16A34A"))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("User Found")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "14532D"))
                        
                        Text("Ready to add this user to your group.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "15803D"))
                    }
                }
                
                // User Preview Card
                HStack(spacing: 12) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(avatarGradient(for: user.id.uuidString))
                            .frame(width: 48, height: 48)
                        
                        Text(user.initials)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(hex: "111827"))
                            .lineLimit(1)
                        
                        Text(user.email)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "6B7280"))
                            .lineLimit(1)
                        
                        Text("ID: \(user.username)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(hex: "9CA3AF"))
                    }
                    
                    Spacer()
                }
                .padding(12)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
                )
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(hex: "F0FDF4"))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "BBF7D0"), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        
        private func avatarGradient(for userId: String) -> LinearGradient {
            let colors: [(Color, Color)] = [
                (Color(hex: "60A5FA"), Color(hex: "2563EB")), // Blue
                (Color(hex: "C084FC"), Color(hex: "9333EA")), // Purple
                (Color(hex: "4ADE80"), Color(hex: "16A34A")), // Green
                (Color(hex: "FB923C"), Color(hex: "EA580C")), // Orange
                (Color(hex: "F472B6"), Color(hex: "DB2777")), // Pink
                (Color(hex: "818CF8"), Color(hex: "4F46E5"))  // Indigo
            ]
            
            let hash = abs(userId.hashValue)
            let index = hash % colors.count
            let (start, end) = colors[index]
            
            return LinearGradient(
                gradient: Gradient(colors: [start, end]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private struct NavigationCardContent: View {
        let iconName: String
        let iconBackground: Color
        let iconColor: Color
        let title: String
        let subtitle: String
        
        var body: some View {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconBackground)
                        .frame(width: 48, height: 48)
                    Image(systemName: iconName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                }
                
                            VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.gray900)
                    
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.gray600)
                }
                
                            Spacer()
                
                            Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color.gray400)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
    
    private struct NavigationCard<Content: View>: View {
        let iconName: String
        let iconBackground: Color
        let iconColor: Color
        let title: String
        let subtitle: String
        var isEnabled: Bool = true
        let destination: () -> Content
        
        init(
            iconName: String,
            iconBackground: Color,
            iconColor: Color,
            title: String,
            subtitle: String,
            isEnabled: Bool = true,
            destination: @escaping () -> Content
        ) {
            self.iconName = iconName
            self.iconBackground = iconBackground
            self.iconColor = iconColor
            self.title = title
            self.subtitle = subtitle
            self.isEnabled = isEnabled
            self.destination = destination
        }
        
        var body: some View {
            SwiftUI.Group {
                if isEnabled {
                    NavigationLink {
                        destination()
                    } label: {
                        NavigationCardContent(
                            iconName: iconName,
                            iconBackground: iconBackground,
                            iconColor: iconColor,
                            title: title,
                            subtitle: subtitle
                        )
                    }
                } else {
                    NavigationCardContent(
                        iconName: iconName,
                        iconBackground: iconBackground,
                        iconColor: iconColor,
                        title: title,
                        subtitle: subtitle
                    )
                    .opacity(0.6)
                }
            }
        }
    }
    
    private struct GroupHelpSheet: View {
        var body: some View {
            NavigationStack {
                List {
                    Section("Group Overview") {
                        Text("This screen shows your group's total spending, members, and quick links to shopping sessions and balances.")
                    }
                    
                    Section("Shopping Sessions") {
                        Text("Shopping sessions are grocery trips where you add items, choose who shares them, and ClearSplit calculates fair splits automatically.")
                    }
                    
                    Section("Balances & Settlement") {
                        Text("Balances show who owes whom based on all expenses. Settlements let you mark payments as paid so everyone can stay in sync.")
                    }
                }
                .navigationTitle("Group Help")
                .navigationBarTitleDisplayMode(.inline)
            }
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

// MARK: - Shopping Sessions Views

@MainActor
final class CreateShoppingSessionViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var shoppingDate: Date = Date()  // Defaults to today, always shown
    @Published var isCreating: Bool = false
    @Published var errorMessage: String?
    
    private let appState: AppState
    private let groupId: UUID
    private let paidByMembershipId: UUID
    
    init(appState: AppState, groupId: UUID, paidByMembershipId: UUID) {
        self.appState = appState
        self.groupId = groupId
        self.paidByMembershipId = paidByMembershipId
    }
    
    var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && title.count <= 100
    }
    
    func createSession() async -> ShoppingSession? {
        guard canCreate else { return nil }
        
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        
        do {
            // Always send the date (defaults to today if user didn't change it)
            let session = try await appState.createShoppingSession(
                groupId: groupId,
                title: title.trimmingCharacters(in: .whitespaces),
                paidBy: paidByMembershipId,
                shoppingDate: shoppingDate,
                totalAmount: nil
            )
            return session
        } catch {
            errorMessage = "Failed to create session: \(error.localizedDescription)"
            return nil
        }
    }
}

struct CreateShoppingSessionView: View {
    @StateObject private var viewModel: CreateShoppingSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showHelp = false
    @State private var showDatePicker = false
    @FocusState private var isTitleFocused: Bool
    
    let onCreated: () -> Void
    
    init(appState: AppState, groupId: UUID, paidByMembershipId: UUID, onCreated: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: CreateShoppingSessionViewModel(
            appState: appState,
            groupId: groupId,
            paidByMembershipId: paidByMembershipId
        ))
        self.onCreated = onCreated
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Background
            Color(hex: "F9FAFB")
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    formCard
                    informationBox
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            
            createButton
            helpButton
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("New Shopping Session")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(hex: "111827"))
                    .tracking(-0.3)
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: "111827"))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                VStack {
                    DatePicker(
                        "Select Date",
                        selection: $viewModel.shoppingDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()
                    
                    Spacer()
                }
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .alert("Help", isPresented: $showHelp) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("A shopping session represents a single grocery trip. Give it a memorable name and set the date. After creation, you can add items and specify who shares each expense.")
        }
        .onAppear {
            // Auto-focus title field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
        }
    }
    
    // MARK: - Subviews
    
    private var formCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            tripTitleField
            dateField
        }
        .padding(24)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    private var tripTitleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trip Title")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "111827"))
                .tracking(-0.2)
            
            TextField("e.g., Weekly Groceries, Costco Run", text: $viewModel.title)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color(hex: "111827"))
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(isTitleFocused ? Color.white : Color(hex: "F3F4F6"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isTitleFocused ? Color(hex: "3B82F6") : Color.clear, lineWidth: isTitleFocused ? 2 : 0)
                )
                .cornerRadius(12)
                .focused($isTitleFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onChange(of: viewModel.title) { _ in
                    if viewModel.title.count > 100 {
                        viewModel.title = String(viewModel.title.prefix(100))
                    }
                }
            
            HStack {
                Text("Give this shopping trip a memorable name")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(hex: "6B7280"))
                
                Spacer()
                
                if !viewModel.title.isEmpty {
                    Text("\(viewModel.title.count)/100")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(viewModel.title.count > 100 ? Color.red : Color(hex: "6B7280"))
                }
            }
        }
    }
    
    private var dateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date (Optional)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "111827"))
                .tracking(-0.2)
            
            Button(action: { showDatePicker = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(Color(hex: "6B7280"))
                        .frame(width: 20, height: 20)
                    
                    Text(formatDateForDisplay(viewModel.shoppingDate))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Color(hex: "111827"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Color(hex: "9CA3AF"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color(hex: "F3F4F6"))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            
            Text("Defaults to today if not set")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color(hex: "6B7280"))
        }
    }
    
    private var informationBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Next steps: ")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "1E3A8A"))
            + Text("After creating this session, you'll be able to add items, upload receipts, and set who shares each item.")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color(hex: "1E3A8A"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: "EFF6FF"))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "BFDBFE"), lineWidth: 1)
        )
        .cornerRadius(12)
    }
    
    private var createButton: some View {
        VStack {
            Spacer()
            Button(action: {
                Task {
                    if await viewModel.createSession() != nil {
                        onCreated()
                    }
                }
            }) {
                buttonContent
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(buttonBackground)
                    .cornerRadius(16)
                    .shadow(color: buttonShadowColor, radius: 12, x: 0, y: 4)
            }
            .disabled(!viewModel.canCreate || viewModel.isCreating)
            .foregroundColor(viewModel.canCreate && !viewModel.isCreating ? .white : Color(hex: "6B7280"))
            .padding(.horizontal, 16)
            .padding(.bottom, 34)
        }
    }
    
    private var buttonContent: some View {
        HStack {
            if viewModel.isCreating {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.9)
                Text("Creating...")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            } else {
                Text("Create Session")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .tracking(-0.3)
            }
        }
    }
    
    @ViewBuilder
    private var buttonBackground: some View {
        if viewModel.canCreate && !viewModel.isCreating {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "3B82F6"),
                    Color(hex: "2563EB")
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color(hex: "D1D5DB")
        }
    }
    
    private var buttonShadowColor: Color {
        viewModel.canCreate && !viewModel.isCreating 
            ? Color(hex: "3B82F6").opacity(0.25) 
            : Color.clear
    }
    
    private var helpButton: some View {
        Button(action: { showHelp = true }) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Color(hex: "1F2937"))
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.trailing, 20)
        .padding(.bottom, 110)
    }
    
    private func formatDateForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: date)
    }
}

@MainActor
final class ShoppingSessionsViewModel: ObservableObject {
    @Published var sessions: [ShoppingSession] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let appState: AppState
    private let groupId: UUID
    
    init(appState: AppState, groupId: UUID) {
        self.appState = appState
        self.groupId = groupId
    }
    
    func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        
        do {
            try await appState.loadShoppingSessions(groupId: groupId)
            var loadedSessions = appState.shoppingSessionsByGroupId[groupId] ?? []
            // Sort by date (newest first)
            loadedSessions.sort { session1, session2 in
                let date1 = parseDateString(session1.shoppingDate) ?? session1.createdAt
                let date2 = parseDateString(session2.shoppingDate) ?? session2.createdAt
                return date1 > date2
            }
            sessions = loadedSessions
        } catch {
            errorMessage = "Failed to load shopping sessions."
        }
    }
    
    private func parseDateString(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

struct ShoppingSessionsListView: View {
    @StateObject private var viewModel: ShoppingSessionsViewModel
    @State private var showingCreateSession = false
    @State private var isShowingHelp = false
    
    let appState: AppState
    let groupId: UUID
    let paidByMembershipId: UUID
    
    init(appState: AppState, groupId: UUID, paidByMembershipId: UUID) {
        self.appState = appState
        self.groupId = groupId
        self.paidByMembershipId = paidByMembershipId
        _viewModel = StateObject(wrappedValue: ShoppingSessionsViewModel(appState: appState, groupId: groupId))
    }
    
    private var members: [Membership] {
        appState.membershipsByGroupId[groupId] ?? []
    }
    
    private var currentUserId: UUID? {
        appState.user?.id
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Background
            Color(hex: "F9FAFB")
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.isLoading && viewModel.sessions.isEmpty {
                        // Loading skeleton
                        VStack(spacing: 16) {
                            ForEach(0..<3) { _ in
                                ShoppingSessionCardSkeleton()
                            }
                        }
                        .padding(.top, 16)
                    } else if viewModel.sessions.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "cart.badge.plus")
                                .font(.system(size: 64, weight: .light))
                                .foregroundColor(Color(hex: "9CA3AF"))
                            
                            Text("No Shopping Sessions Yet")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Color(hex: "111827"))
                            
                            Text("Create your first shopping session to start tracking expenses with your group.")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color(hex: "6B7280"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            
                            Button(action: { showingCreateSession = true }) {
                                Text("Create Session")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: 200)
                                    .padding(.vertical, 12)
                                    .background(Color(hex: "2563EB"))
                                    .cornerRadius(8)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.top, 100)
                    } else {
                        // Session cards
                        ForEach(viewModel.sessions) { session in
                            NavigationLink {
                                ShoppingSessionDetailView(
                                    sessionId: session.id,
                                    groupId: groupId,
                                    membershipId: paidByMembershipId
                                )
                                .environmentObject(appState)
                            } label: {
                                ShoppingSessionCard(
                                    session: session,
                                    members: members,
                                    currentUserId: currentUserId
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.top, 16)
                        
                        // Pull down to refresh text
                        Text("Pull down to refresh")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "2563EB"))
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                    }
                }
                .padding(.horizontal, 16)
            }
            .refreshable {
                await viewModel.load()
            }
            
            // Help Button (Bottom Right)
            Button {
                isShowingHelp = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color(hex: "1F2937"))
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.trailing, 20)
            .padding(.bottom, 54)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Shopping Sessions")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(hex: "111827"))
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCreateSession = true }) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "2563EB"))
                            .frame(width: 48, height: 48)
                            .shadow(color: Color(hex: "2563EB").opacity(0.3), radius: 8, x: 0, y: 2)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showingCreateSession) {
            CreateShoppingSessionView(
                appState: appState,
                groupId: groupId,
                paidByMembershipId: paidByMembershipId,
                onCreated: {
                    showingCreateSession = false
                    Task { await viewModel.load() }
                }
            )
        }
        .sheet(isPresented: $isShowingHelp) {
            ShoppingSessionsHelpSheet()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("Retry") { Task { await viewModel.load() } }
            Button("Cancel", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct ShoppingSessionCard: View {
    let session: ShoppingSession
    let members: [Membership]
    let currentUserId: UUID?
    
    private func formatDateString(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: dateString) {
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
        return dateString
    }
    
    private func getPaidByName() -> String {
        // Find the membership that matches paidByMembershipId
        if let membership = members.first(where: { $0.id == session.paidByMembershipId }) {
            // Check if it's the current user
            if let user = membership.user, user.id == currentUserId {
                return "You"
            }
            // Return user's first name or display name
            if let user = membership.user {
                return user.firstName.isEmpty ? user.displayName : user.firstName
            }
            return membership.displayName
        }
        return "Unknown"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Session Name + Amount
            HStack(alignment: .top) {
                Text(session.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "111827"))
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
                
                Spacer()
                
                Text(session.formattedTotal)
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .foregroundColor(Color(hex: "111827"))
            }
            .padding(20)
            
            // Row 2: Date
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(hex: "6B7280"))
                
                Text(formatDateString(session.shoppingDate))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(hex: "6B7280"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            
            // Spacing between rows 2 & 3
            Spacer()
                .frame(height: 12)
            
            // Row 3: Item Count + Paid By
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cart")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(hex: "6B7280"))
                    
                    Text("\(session.items.count) items")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(hex: "6B7280"))
                }
                
                Spacer()
                
                Text("Paid by \(getPaidByName())")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(hex: "4B5563"))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// Loading skeleton card
struct ShoppingSessionCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 150, height: 20)
                
                Spacer()
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 80, height: 24)
            }
            .padding(20)
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "E5E7EB"))
                .frame(width: 100, height: 14)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            
            Spacer()
                .frame(height: 12)
            
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 80, height: 14)
                
                Spacer()
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 100, height: 14)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: 112)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
        )
        .shimmer()
    }
}

// Shimmer effect extension
extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                }
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

// Help sheet for shopping sessions
struct ShoppingSessionsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Shopping Sessions Help")
                        .font(.system(size: 24, weight: .bold))
                        .padding(.bottom, 8)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HelpSection(
                            title: "What are Shopping Sessions?",
                            content: "Shopping sessions track group expenses from grocery trips and shopping. Each session contains items that can be split among group members."
                        )
                        
                        HelpSection(
                            title: "Creating a Session",
                            content: "Tap the + button to create a new shopping session. You'll need to provide a name, date, and who paid for the trip."
                        )
                        
                        HelpSection(
                            title: "Adding Items",
                            content: "Once a session is created, you can add items with prices. Items can be split among multiple members."
                        )
                        
                        HelpSection(
                            title: "Viewing Details",
                            content: "Tap any session card to view its items, participants, and splitting details."
                        )
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private struct HelpSection: View {
        let title: String
        let content: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(hex: "111827"))
                
                Text(content)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(hex: "6B7280"))
            }
        }
    }
}

extension ShoppingSession {
    var formattedTotal: String {
        let dollars = Double(totalCents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

struct CreateShoppingSessionSheet: View {
    let groupId: UUID
    let membershipId: UUID
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var shoppingDate = Date()
    @State private var totalAmountText = ""
    @State private var selectedPayerMembershipId: UUID?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    private var members: [Membership] {
        appState.membershipsByGroupId[groupId] ?? []
    }
    
    private var selectedPayer: UUID {
        selectedPayerMembershipId ?? membershipId
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .disabled(isCreating)
                } header: {
                    Text("Session Details")
                } footer: {
                    Text("e.g., \"Costco Run 1/7\" or \"Weekly Groceries\"")
                }
                
                Section {
                    DatePicker("Shopping Date", selection: $shoppingDate, displayedComponents: .date)
                        .disabled(isCreating)
                } header: {
                    Text("When")
                }
                
                Section {
                    TextField("Total Amount", text: $totalAmountText)
                        .keyboardType(.decimalPad)
                        .disabled(isCreating)
                } header: {
                    Text("Amount")
                } footer: {
                    Text("Optional: Enter total amount for quick splits. Leave empty if you'll add individual items later.")
                }
                
                Section {
                    Picker("Who Paid", selection: $selectedPayerMembershipId) {
                        ForEach(members) { member in
                            Text(member.user?.email ?? "Unknown")
                                .tag(member.id as UUID?)
                        }
                    }
                    .disabled(isCreating)
                } header: {
                    Text("Payment")
                } footer: {
                    Text("Select who paid for this shopping trip")
                }
                
                Section {
                    Text("You'll be able to set participants and add items after creating the session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Shopping Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createSession() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let message = errorMessage {
                    Text(message)
                }
            }
            .task {
                // Load members when sheet appears
                if members.isEmpty {
                    try? await appState.loadMembers(groupId: groupId)
                }
                // Set default payer to current user
                if selectedPayerMembershipId == nil {
                    selectedPayerMembershipId = membershipId
                }
            }
        }
    }
    
    private func createSession() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        // Parse total amount if provided
        let totalAmount: Double? = {
            let trimmed = totalAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Double(trimmed)
        }()
        
        isCreating = true
        defer { isCreating = false }
        
        do {
            _ = try await appState.createShoppingSession(
                groupId: groupId,
                title: trimmedTitle,
                paidBy: selectedPayer,
                shoppingDate: shoppingDate,
                totalAmount: totalAmount
            )
            dismiss()
        } catch {
            errorMessage = "Failed to create session: \(error.localizedDescription)"
            showError = true
        }
    }
}

struct ShoppingSessionDetailView: View {
    let sessionId: UUID
    let groupId: UUID
    let membershipId: UUID
    @EnvironmentObject private var appState: AppState
    
    @State private var session: ShoppingSession?
    @State private var showingAddItem = false
    @State private var showingSetParticipants = false
    @State private var showingReceiptUpload = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var groupMemberships: [Membership] = []
    
    var body: some View {
        ZStack {
            if isLoading && session == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let session = session {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Blue Gradient Hero Card
                            TotalAmountHeroCardOld(
                                totalCents: session.totalCents,
                                paidByMembershipId: session.paidByMembershipId,
                                groupMemberships: groupMemberships,
                                currentUserId: appState.user?.id
                            )
                            
                            // Content Area
                            VStack(spacing: 16) {
                                // Participants Card
                                ParticipantsDetailCardOld(
                                    participants: session.participants,
                                    groupMemberships: groupMemberships,
                                    currentUserId: appState.user?.id,
                                    membershipId: membershipId,
                                    onSetParticipants: {
                                        showingSetParticipants = true
                                    }
                                )
                                
                                // Receipts Card
                                ReceiptsDetailCardOld(
                                    receipts: session.receipts,
                                    onUploadTap: {
                                        showingReceiptUpload = true
                                    }
                                )
                                
                                // Items Card
                                ItemsDetailCardOld(
                                    items: session.items,
                                    participants: session.participants,
                                    groupMemberships: groupMemberships,
                                    currentUserId: appState.user?.id,
                                    membershipId: membershipId,
                                    onItemTap: { itemId in
                                        // TODO: Navigate to edit item
                                    }
                                )
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 100) // Space for fixed button
                        }
                    }
                    .background(Color.white)
                    
                    // Fixed Add Item Button
                    AddItemFixedButtonOld {
                        showingAddItem = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.gray400)
                    Text("Session Not Found")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.gray900)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    if let session = session {
                        Text(session.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.gray900)
                        
                        if let dateString = session.shoppingDate,
                           let date = parseDate(dateString) {
                            Text(formatDate(date))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.gray500)
                        }
                    }
                }
            }
        }
        .task {
            await loadSession()
            await loadGroupMemberships()
        }
        .sheet(isPresented: $showingAddItem) {
            if let session = session {
                AddItemSheet(
                    sessionId: session.id,
                    groupId: groupId,
                    membershipId: membershipId,
                    participants: session.participants
                )
            }
        }
        .sheet(isPresented: $showingSetParticipants) {
            SetParticipantsSheet(
                sessionId: sessionId,
                groupId: groupId,
                currentParticipantIds: session?.participants.map { $0.membershipId } ?? []
            )
        }
        .sheet(isPresented: $showingReceiptUpload) {
            if let session = session {
                ReceiptUploadView(
                    sessionId: session.id,
                    groupId: groupId,
                    onUploadComplete: { receipt in
                        Task {
                            await loadSession()
                            showingReceiptUpload = false
                        }
                    },
                    onBack: {
                        showingReceiptUpload = false
                    }
                )
                .environmentObject(appState)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let message = errorMessage {
                Text(message)
            }
        }
    }
    
    private func loadSession() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            session = try await appState.refreshShoppingSession(sessionId: sessionId, groupId: groupId)
        } catch {
            errorMessage = "Failed to load session: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func loadGroupMemberships() async {
        do {
            try await appState.loadMembers(groupId: groupId)
            groupMemberships = appState.membershipsByGroupId[groupId] ?? []
        } catch {
            // Silently fail
        }
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Total Amount Hero Card (Old)

struct TotalAmountHeroCardOld: View {
    let totalCents: Int
    let paidByMembershipId: UUID
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label
            Text("Total Amount")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
                .padding(.bottom, 8)
            
            // Amount
            Text(formatCurrency(cents: totalCents, currency: "USD"))
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 12)
            
            // Paid by
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                
                Text(paidByText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(hex: "2563EB"), Color(hex: "1D4ED8")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(24, corners: [.bottomLeft, .bottomRight])
    }
    
    private var paidByText: String {
        guard let currentUserId = currentUserId else {
            return "Paid by Unknown"
        }
        
        guard let membership = groupMemberships.first(where: { $0.id == paidByMembershipId }),
              let user = membership.user else {
            return "Paid by Unknown"
        }
        
        if user.id == currentUserId {
            return "Paid by You"
        }
        
        return "Paid by \(user.firstName) \(user.lastName)"
    }
}

// MARK: - Participants Detail Card (Old)

struct ParticipantsDetailCardOld: View {
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let membershipId: UUID
    let onSetParticipants: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray700)
                    
                    Text("Participants")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.gray900)
                }
                
                Spacer()
                
                // Count Badge
                Text("\(participants.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue700)
                    .frame(width: 24, height: 24)
                    .background(Color.blue50)
                    .clipShape(Circle())
            }
            
            // Participants List
            if participants.isEmpty {
                Button(action: onSetParticipants) {
                    HStack(spacing: 8) {
                        ZStack {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.blue600)
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue600)
                                .offset(x: 8, y: 6)
                        }
                        Text("Set Participants")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue600)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray200, lineWidth: 1)
                    )
                }
            } else {
                HStack(spacing: 16) {
                    ForEach(participants) { participant in
                        ParticipantAvatarViewOld(
                            participant: participant,
                            membership: groupMemberships.first(where: { $0.id == participant.membershipId }),
                            currentUserId: currentUserId,
                            membershipId: membershipId
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Participant Avatar View (Old)

struct ParticipantAvatarViewOld: View {
    let participant: ShoppingSessionParticipant
    let membership: Membership?
    let currentUserId: UUID?
    let membershipId: UUID
    
    var body: some View {
        VStack(spacing: 6) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 40, height: 40)
                
                Text(displayInitial)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Name
            Text(displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray700)
        }
    }
    
    private var displayName: String {
        if participant.membershipId == membershipId {
            return "You"
        }
        if let membership = membership,
           let user = membership.user {
            return "\(user.firstName) \(user.lastName)"
        }
        return "Member"
    }
    
    private var displayInitial: String {
        if participant.membershipId == membershipId {
            return "Y"
        }
        if let membership = membership,
           let user = membership.user {
            return String(user.firstName.prefix(1)).uppercased()
        }
        return String(participant.membershipId.uuidString.prefix(1)).uppercased()
    }
    
    private var avatarGradient: LinearGradient {
        let colors = [
            [Color(hex: "60A5FA"), Color(hex: "2563EB")],
            [Color(hex: "38BDF8"), Color(hex: "0284C7")],
            [Color(hex: "3B82F6"), Color(hex: "1D4ED8")],
            [Color(hex: "6366F1"), Color(hex: "4F46E5")],
            [Color(hex: "8B5CF6"), Color(hex: "7C3AED")],
            [Color(hex: "EC4899"), Color(hex: "DB2777")],
            [Color(hex: "10B981"), Color(hex: "059669")],
            [Color(hex: "F59E0B"), Color(hex: "D97706")]
        ]
        
        let hash = participant.membershipId.uuidString.hashValue
        let index = abs(hash) % colors.count
        let colorPair = colors[index]
        
        return LinearGradient(
            colors: colorPair,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Receipts Detail Card (Old)

struct ReceiptsDetailCardOld: View {
    let receipts: [ReceiptUpload]
    let onUploadTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray700)
                    
                    Text("Receipts")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.gray900)
                }
                
                Spacer()
                
                // Camera Button
                Button(action: onUploadTap) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue600)
                        .frame(width: 44, height: 44)
                }
            }
            
            // Receipt Content
            if receipts.isEmpty {
                // Empty State
                Button(action: onUploadTap) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray100)
                            .frame(width: 80, height: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                                    .foregroundColor(.gray300)
                            )
                        
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray400)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // Receipt Thumbnails
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(receipts) { receipt in
                            ReceiptThumbnailView(receipt: receipt)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Items Detail Card (Old)

struct ItemsDetailCardOld: View {
    let items: [ShoppingItem]
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let membershipId: UUID
    let onItemTap: (UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Items")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.gray900)
                
                Spacer()
                
                // Count Badge
                Text("\(items.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray700)
                    .frame(width: 24, height: 24)
                    .background(Color.gray100)
                    .clipShape(Circle())
            }
            
            // Items List
            if items.isEmpty {
                Text("No items yet")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 16) {
                    ForEach(items) { item in
                        ItemDetailRowOld(
                            item: item,
                            participants: participants,
                            groupMemberships: groupMemberships,
                            currentUserId: currentUserId,
                            membershipId: membershipId,
                            onTap: {
                                onItemTap(item.id)
                            }
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Item Detail Row (Old)

struct ItemDetailRowOld: View {
    let item: ShoppingItem
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let membershipId: UUID
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Row 1: Name and Total
                HStack {
                    Text(item.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray900)
                    
                    Spacer()
                    
                    Text(formatCurrency(cents: item.totalCents, currency: "USD"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.gray900)
                }
                
                // Row 2: Unit Price × Quantity
                if let unitPriceCents = item.unitPriceCents {
                    Text("\(formatCurrency(cents: unitPriceCents, currency: "USD")) × \(item.quantity)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray500)
                }
                
                // Row 3: Shared by
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shared by:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray600)
                    
                    // Participant Badges
                    HStack(spacing: 8) {
                        ForEach(sharedByMemberships) { membership in
                            ParticipantBadgeOld(
                                membership: membership,
                                currentUserId: currentUserId,
                                membershipId: membershipId
                            )
                        }
                    }
                }
                
                // Row 4: Your Share
                HStack {
                    Text("Your share:")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray600)
                    
                    Spacer()
                    
                    Text(formatCurrency(cents: userShareCents, currency: "USD"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray900)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray50)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray200, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var sharedByMemberships: [Membership] {
        let membershipIds = item.splits.map { $0.membershipId }
        return groupMemberships.filter { membershipIds.contains($0.id) }
    }
    
    private var userShareCents: Int {
        if let split = item.splits.first(where: { $0.membershipId == membershipId }) {
            return split.shareCents
        }
        return 0
    }
}

// MARK: - Participant Badge (Old)

struct ParticipantBadgeOld: View {
    let membership: Membership
    let currentUserId: UUID?
    let membershipId: UUID
    
    var body: some View {
        Text(displayName)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.blue700)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.blue50)
            .cornerRadius(14)
    }
    
    private var displayName: String {
        if membership.id == membershipId {
            return "You"
        }
        if let user = membership.user {
            return "\(user.firstName) \(user.lastName)"
        }
        return "Member"
    }
}

// MARK: - Add Item Fixed Button (Old)

struct AddItemFixedButtonOld: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Add Item")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.blue600)
            .cornerRadius(26)
            .shadow(color: Color.blue600.opacity(0.25), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Corner Radius Extension (Old)

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct SetParticipantsSheet: View {
    let sessionId: UUID
    let groupId: UUID
    let currentParticipantIds: [UUID]
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedMembershipIds: Set<UUID> = []
    @State private var newMemberEmail = ""
    @State private var isAddingMember = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var members: [Membership] {
        appState.membershipsByGroupId[groupId] ?? []
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Email address", text: $newMemberEmail)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .disabled(isAddingMember)
                        
                        Button("Add") {
                            Task { await addMember() }
                        }
                        .disabled(newMemberEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingMember)
                    }
                } header: {
                    Text("Add Participant by Email")
                } footer: {
                    Text("Enter the email of a registered user to add them as a participant")
                }
                
                Section {
                    if members.isEmpty {
                        Text("Loading members...")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(members) { member in
                            Button {
                                if selectedMembershipIds.contains(member.id) {
                                    selectedMembershipIds.remove(member.id)
                                } else {
                                    selectedMembershipIds.insert(member.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedMembershipIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedMembershipIds.contains(member.id) ? .blue : .gray)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.displayName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        if let email = member.user?.email {
                                            Text(email)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Select Participants")
                } footer: {
                    Text("Select who participated in this shopping session")
                }
            }
            .navigationTitle("Set Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveParticipants() }
                    }
                    .disabled(selectedMembershipIds.isEmpty || isSaving)
                }
            }
            .task {
                selectedMembershipIds = Set(currentParticipantIds)
                if members.isEmpty {
                    try? await appState.loadMembers(groupId: groupId)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let message = errorMessage {
                    Text(message)
                }
            }
        }
    }
    
    private func addMember() async {
        let trimmedEmail = newMemberEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return }
        
        isAddingMember = true
        defer { isAddingMember = false }
        
        do {
            // Add member to group (backend will verify email exists)
            let membership = try await appState.addMemberToGroup(
                groupId: groupId,
                email: trimmedEmail
            )
            
            // Auto-select the newly added member
            selectedMembershipIds.insert(membership.id)
            
            // Clear the email field
            newMemberEmail = ""
            
        } catch let error as APIError {
            switch error {
            case .serverError(let statusCode, let message):
                if statusCode == 404 {
                    errorMessage = "No user found with email '\(trimmedEmail)'. They must register first."
                } else if statusCode == 400 && message?.contains("already a member") == true {
                    errorMessage = "User is already a member of this group"
                } else {
                    errorMessage = message ?? "Failed to add member"
                }
            default:
                errorMessage = "Failed to add member: \(error.localizedDescription)"
            }
            showError = true
        } catch {
            errorMessage = "Failed to add member: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func saveParticipants() async {
        isSaving = true
        defer { isSaving = false }
        
        do {
            _ = try await appState.setSessionParticipants(
                sessionId: sessionId,
                groupId: groupId,
                membershipIds: Array(selectedMembershipIds)
            )
            dismiss()
        } catch {
            errorMessage = "Failed to save participants: \(error.localizedDescription)"
            showError = true
        }
    }
}

struct AddItemSheet: View {
    let sessionId: UUID
    let groupId: UUID
    let membershipId: UUID
    let participants: [ShoppingSessionParticipant]
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var itemName = ""
    @State private var quantity = "1"
    @State private var priceText = ""
    @State private var selectedSharerIds: Set<UUID> = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var isValid: Bool {
        !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !priceText.isEmpty &&
        (Decimal(string: priceText) ?? 0) > 0 &&
        (Int(quantity) ?? 0) >= 1 &&
        !selectedSharerIds.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item name", text: $itemName)
                        .disabled(isCreating)
                    
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.numberPad)
                        .disabled(isCreating)
                    
                    HStack {
                        Text("$")
                        TextField("Price", text: $priceText)
                            .keyboardType(.decimalPad)
                            .disabled(isCreating)
                    }
                }
                
                Section("Who's Sharing This Item?") {
                    if participants.isEmpty {
                        Text("Set participants first")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(participants) { participant in
                            Button {
                                if selectedSharerIds.contains(participant.membershipId) {
                                    selectedSharerIds.remove(participant.membershipId)
                                } else {
                                    selectedSharerIds.insert(participant.membershipId)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedSharerIds.contains(participant.membershipId) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedSharerIds.contains(participant.membershipId) ? .blue : .gray)
                                    
                                    Text(participant.membershipId == membershipId ? "You" : String(participant.membershipId.uuidString.prefix(8)))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if !priceText.isEmpty, let price = Decimal(string: priceText), !selectedSharerIds.isEmpty {
                                        let totalCents = Int(truncating: (price * Decimal(100)) as NSDecimalNumber)
                                        let shareCents = totalCents / selectedSharerIds.count
                                        Text("$\(String(format: "%.2f", Double(shareCents) / 100.0))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await createItem() }
                    }
                    .disabled(!isValid || isCreating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let message = errorMessage {
                    Text(message)
                }
            }
        }
    }
    
    private func createItem() async {
        let trimmedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let price = Decimal(string: priceText),
              price > 0,
              let qty = Int(quantity),
              qty >= 1 else { return }
        
        isCreating = true
        defer { isCreating = false }
        
        do {
            let totalCents = Int(truncating: (price * Decimal(100)) as NSDecimalNumber)
            let item = try await appState.createShoppingItem(
                sessionId: sessionId,
                groupId: groupId,
                name: trimmedName,
                quantity: qty,
                totalCents: totalCents
            )
            
            // Set sharers
            _ = try await appState.setItemSharers(
                itemId: item.id,
                sessionId: sessionId,
                groupId: groupId,
                membershipIds: Array(selectedSharerIds)
            )
            
            dismiss()
        } catch {
            errorMessage = "Failed to create item: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Receipt Upload Sheet

struct ReceiptUploadView: View {
    let sessionId: UUID
    let groupId: UUID
    @EnvironmentObject private var appState: AppState
    let onUploadComplete: (ReceiptUpload) -> Void
    let onBack: () -> Void
    
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.gray50
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        if selectedImage == nil {
                            emptyStateView
                        } else {
                            previewStateView
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 80)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.gray900)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Upload Receipt")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.gray900)
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPickerView(selectedImage: $selectedImage)
            }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePickerView(sourceType: .camera, selectedImage: $selectedImage)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue200)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue600)
                }
                .padding(.bottom, 12)
                
                Text("Add Receipt Photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.gray900)
                    .padding(.bottom, 4)
                
                Text("Take a photo or select one from your gallery to add items automatically")
                    .font(.system(size: 14))
                    .foregroundColor(.gray600)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .padding(.bottom, 32)
            }
            .padding(.top, 40)
            
            VStack(spacing: 16) {
                Button(action: {
                    showCamera = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                        
                        Text("Take Photo")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: 448)
                    .frame(height: 96)
                    .background(Color.blue600)
                    .cornerRadius(16)
                }
                
                Button(action: {
                    showPhotoPicker = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                            .foregroundColor(.gray900)
                        
                        Text("Choose from Gallery")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.gray900)
                    }
                    .frame(maxWidth: 448)
                    .frame(height: 96)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray300, lineWidth: 2)
                    )
                    .cornerRadius(16)
                }
            }
            .padding(.top, 32)
        }
    }
    
    private var previewStateView: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray900)
                    .frame(minHeight: 400, maxHeight: 600)
                    .frame(maxWidth: .infinity)
                
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(minHeight: 400, maxHeight: 600)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(16)
                        .clipped()
                }
                
                Button(action: {
                    withAnimation {
                        selectedImage = nil
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.gray900.opacity(0.8))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(16)
            }
            
            VStack(spacing: 12) {
                Button(action: handleUpload) {
                    HStack(spacing: 8) {
                        if isUploading {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 20, height: 20)
                            
                            Text("Processing...")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.white)
                        } else {
                            Text("Use This Photo")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(isUploading ? Color.blue500 : Color.blue600)
                    .cornerRadius(12)
                }
                .disabled(isUploading)
                
                Button(action: {
                    showPhotoPicker = true
                }) {
                    Text("Choose Different Photo")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.gray900)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(isUploading ? Color.gray100 : Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray300, lineWidth: 1)
                        )
                        .cornerRadius(12)
                }
                .disabled(isUploading)
            }
            
            Text("We'll automatically extract items and prices from your receipt")
                .font(.system(size: 14))
                .foregroundColor(.gray600)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
        }
    }
    
    private func handleUpload() {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Failed to process image"
            showError = true
            return
        }
        
        isUploading = true
        
        Task {
            do {
                let receipt = try await appState.uploadReceipt(
                    sessionId: sessionId,
                    groupId: groupId,
                    imageData: imageData,
                    contentType: "image/jpeg"
                )
                
                await MainActor.run {
                    isUploading = false
                    onUploadComplete(receipt)
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    errorMessage = "Failed to upload receipt: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

// MARK: - Photo Picker Components

struct PhotoPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView
        
        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                if let image = image as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image
                    }
                }
            }
        }
    }
}

struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        
        init(_ parent: ImagePickerView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                DispatchQueue.main.async {
                    self.parent.selectedImage = image
                }
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Receipt Thumbnail View

struct ReceiptThumbnailView: View {
    let receipt: ReceiptUpload
    @EnvironmentObject private var appState: AppState
    
    @State private var imageURL: URL?
    @State private var isLoading = true
    @State private var loadError = false
    
    var body: some View {
        contentView
            .task {
                await loadImageURL()
            }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if let url = imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    loadingView
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray200, lineWidth: 1)
                        )
                case .failure:
                    errorView
                @unknown default:
                    loadingView
                }
            }
        } else if isLoading {
            loadingView
        } else {
            errorView
        }
    }
    
    private var loadingView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray200)
            .frame(width: 80, height: 80)
            .overlay(
                ProgressView()
                    .scaleEffect(0.8)
            )
    }
    
    private var errorView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray200)
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.gray400)
            )
    }
    
    private func loadImageURL() async {
        do {
            let urlString = try await appState.getReceiptDownloadURL(receiptUploadId: receipt.id)
            if let url = URL(string: urlString) {
                await MainActor.run {
                    self.imageURL = url
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.loadError = true
                    self.isLoading = false
                }
            }
        } catch {
            print("[ReceiptThumbnailView] Failed to load image URL: \(error)")
            await MainActor.run {
                self.loadError = true
                self.isLoading = false
            }
        }
    }
}

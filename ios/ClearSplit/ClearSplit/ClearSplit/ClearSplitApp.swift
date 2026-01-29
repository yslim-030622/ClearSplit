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
    let firstName: String
    let lastName: String
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

    func signup(email: String, password: String, firstName: String, lastName: String) async throws {
        print("[AppState] Signup started for: \(email)")
        isLoading = true
        defer { isLoading = false }
        
        struct SignupRequest: Encodable {
            let email: String
            let password: String
            let first_name: String
            let last_name: String
            
            enum CodingKeys: String, CodingKey {
                case email, password
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
    
    func addMemberToGroup(groupId: UUID, email: String) async throws -> Membership {
        print("[AppState] Adding member \(email) to group: \(groupId)")
        let membership = try await apiClient.addGroupMember(groupId: groupId, email: email)
        
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
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
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
                                
                                TextField("you@example.com", text: $email)
                                    .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
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
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @FocusState private var focusedField: Field?
    
    enum Field {
        case firstName, lastName, email, password
    }
    
    private var isFormValid: Bool {
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
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName
            )
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
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
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
                        currentUserId: currentUserId
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
                        ShoppingSessionsListView(group: group, membershipId: membershipId)
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
        
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color.gray700)
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.gray900)
                            Spacer()
                }
                
                if members.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No members yet")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color.gray600)
                        Text("Invite your roommates to start splitting expenses.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.gray500)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 16) {
                        ForEach(members) { member in
                            MemberRow(
                                member: member,
                                isCurrentUser: member.userId == currentUserId
                            )
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
    
    private struct MemberRow: View {
        let member: Membership
        let isCurrentUser: Bool
        
        private var displayName: String {
            if isCurrentUser {
                return "You"
            }
            if let user = member.user {
                let fullName = "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
                if !fullName.isEmpty {
                    return fullName
                }
                return user.email
            }
            return member.displayName
        }
        
        private var initials: String {
            if let user = member.user {
                let firstInitial = user.firstName.first.map(String.init) ?? ""
                let lastInitial = user.lastName.first.map(String.init) ?? ""
                let combined = (firstInitial + lastInitial)
                if !combined.isEmpty {
                    return combined
                }
            }
            return String(displayName.prefix(1)).uppercased()
        }
        
        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue500)
                        .frame(width: 40, height: 40)
                    Text(initials)
                        .font(.system(size: initials.count > 1 ? 14 : 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text(displayName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color.gray900)
                
                Spacer()
                
                if isCurrentUser {
                    Text("You")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.blue700)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue50)
                        .cornerRadius(8)
                }
            }
            .frame(height: 40)
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

struct ShoppingSessionsListView: View {
    let group: Group
    let membershipId: UUID
    @EnvironmentObject private var appState: AppState
    @State private var showingCreateSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var sessions: [ShoppingSession] {
        appState.shoppingSessionsByGroupId[group.id] ?? []
    }
    
    var body: some View {
        List {
            if sessions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "cart")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("No Shopping Sessions")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap + to create your first shopping session")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        ShoppingSessionDetailView(
                            sessionId: session.id,
                            groupId: group.id,
                            membershipId: membershipId
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(session.title)
                                    .font(.headline)
                                Spacer()
                                Text(session.displayTotal)
                                    .font(.headline)
                                    .foregroundColor(.blue)
                            }
                            
                            HStack {
                                Label("\(session.items.count) items", systemImage: "cart")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(session.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Shopping Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCreateSession = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateSession) {
            CreateShoppingSessionSheet(
                groupId: group.id,
                membershipId: membershipId
            )
        }
        .task {
            await loadSessions()
        }
        .refreshable {
            await loadSessions()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let message = errorMessage {
                Text(message)
            }
        }
    }
    
    private func loadSessions() async {
        do {
            try await appState.loadShoppingSessions(groupId: group.id)
        } catch {
            errorMessage = "Failed to load sessions: \(error.localizedDescription)"
            showError = true
        }
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
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        ZStack {
            if let session = session {
                List {
                    // Summary Section
                    Section {
                        HStack {
                            Text("Total")
                                .font(.headline)
                            Spacer()
                            Text(session.displayTotal)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        
                        HStack {
                            Text("Participants")
                            Spacer()
                            Text("\(session.participants.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Participants Section
                    Section("Participants") {
                        if session.participants.isEmpty {
                            Button {
                                showingSetParticipants = true
                            } label: {
                                HStack {
                                    Image(systemName: "person.2.badge.gearshape")
                                        .foregroundColor(.blue)
                                    Text("Set Participants")
                                    Spacer()
                                }
                            }
                        } else {
                            ForEach(session.participants) { participant in
                                HStack {
                                    Image(systemName: "person.circle.fill")
                                        .foregroundColor(participant.membershipId == membershipId ? .green : .blue)
                                    Text(participant.membershipId == membershipId ? "You" : String(participant.membershipId.uuidString.prefix(8)))
                                }
                            }
                            
                            Button {
                                showingSetParticipants = true
                            } label: {
                                HStack {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                    Text("Edit Participants")
                                }
                            }
                        }
                    }
                    
                    // Items Section
                    Section("Items") {
                        if session.items.isEmpty {
                            Text("No items yet")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(session.items) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(item.name)
                                            .font(.headline)
                                        Spacer()
                                        Text(item.displayTotal)
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    HStack {
                                        Text("Qty: \(item.quantity)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("•")
                                            .foregroundColor(.secondary)
                                        Text("Split \(item.splits.count) ways")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if !item.splits.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(item.splits) { split in
                                                HStack {
                                                    Text(split.membershipId == membershipId ? "You" : String(split.membershipId.uuidString.prefix(8)))
                                                        .font(.caption2)
                                                        .foregroundColor(split.membershipId == membershipId ? .green : .secondary)
                                                    Spacer()
                                                    Text(split.displayAmount)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                        .padding(.leading, 12)
                                        .padding(.top, 4)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .navigationTitle(session.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingAddItem = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(session.participants.isEmpty)
                    }
                }
            } else if isLoading {
                ProgressView("Loading...")
            } else {
                VStack {
                    Text("Session not found")
                        .foregroundColor(.secondary)
                }
            }
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
        .task {
            await loadSession()
        }
        .refreshable {
            await loadSession()
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

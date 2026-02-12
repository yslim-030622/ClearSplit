import Foundation
import Combine

enum AppStateError: Error {
    case invalidItemInput
    case invalidParticipants
}

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published state
    @Published var user: User?
    @Published var isLoading = false
    @Published var authError: String?

    @Published var groups: [Group] = []
    @Published var expensesByGroupId: [UUID: [Expense]] = [:]
    @Published var membershipsByGroupId: [UUID: [Membership]] = [:]
    @Published var settlementsByGroupId: [UUID: [Settlement]] = [:]
    @Published var shoppingSessionsByGroupId: [UUID: [ShoppingSession]] = [:]
    @Published var isLoadingExpenses = false
    @Published var isLoadingBalances = false
    @Published var isLoadingShopping = false

    // MARK: - Dependencies
    let apiClient: APIClient
    let authService: AuthServicing
    let groupsService: GroupsServicing
    let shoppingService: ShoppingServicing

    init(
        apiClient: APIClient = APIClient(),
        authService: AuthServicing? = nil,
        groupsService: GroupsServicing? = nil,
        shoppingService: ShoppingServicing? = nil
    ) {
        self.apiClient = apiClient
        self.authService = authService ?? AuthService(client: apiClient)
        self.groupsService = groupsService ?? GroupsService(client: apiClient)
        self.shoppingService = shoppingService ?? ShoppingService(client: apiClient)
    }

    // MARK: - Session lifecycle
    func bootstrap() async {
        guard await apiClient.currentTokens() != nil else {
            user = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            user = try await authService.me()
            try await loadGroups()
        } catch {
            authError = "Session expired"
            user = nil
            await apiClient.clearTokens()
        }
    }

    func verifySession() async {
        await bootstrap()
    }

    func login(identifier: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        let (tokens, me) = try await authService.login(identifier: identifier, password: password)
        await apiClient.store(tokens: tokens)
        user = me
        try await loadGroups()
    }

    func signup(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        let tokens = try await authService.signup(email: email, password: password)
        await apiClient.store(tokens: tokens)
        user = try await authService.me()
        try await loadGroups()
    }

    func logout() async {
        user = nil
        groups = []
        expensesByGroupId = [:]
        membershipsByGroupId = [:]
        settlementsByGroupId = [:]
        shoppingSessionsByGroupId = [:]
        await apiClient.clearTokens()
    }

    // MARK: - Groups
    func loadGroups() async throws {
        groups = try await groupsService.listGroups()
    }

    func createGroup(name: String, currency: String) async throws -> Group {
        struct CreateGroupRequest: Encodable { let name: String; let currency: String }
        let group: Group = try await apiClient.request(APIRequest(
            path: "groups",
            method: "POST",
            body: CreateGroupRequest(name: name, currency: currency)
        ))
        try await loadGroups()
        return group
    }

    func deleteGroup(groupId: UUID) async throws {
        let _: Group = try await apiClient.request(APIRequest(
            path: "groups/\(groupId.uuidString)",
            method: "DELETE"
        ))
        groups.removeAll { $0.id == groupId }
        expensesByGroupId[groupId] = nil
        membershipsByGroupId[groupId] = nil
        settlementsByGroupId[groupId] = nil
        shoppingSessionsByGroupId[groupId] = nil
    }

    // MARK: - Members
    func loadMembers(groupId: UUID) async throws {
        let members: [Membership] = try await apiClient.request(APIRequest(
            path: "groups/\(groupId.uuidString)/members"
        ))
        membershipsByGroupId[groupId] = members
    }

    func addMemberToGroup(groupId: UUID, username: String? = nil, email: String? = nil) async throws -> Membership {
        struct AddMemberRequest: Encodable {
            let username: String?
            let email: String?
            let role: String = "member"
        }
        let membership: Membership = try await apiClient.request(APIRequest(
            path: "groups/\(groupId.uuidString)/members",
            method: "POST",
            body: AddMemberRequest(username: username, email: email)
        ))
        try await loadMembers(groupId: groupId)
        return membership
    }

    func previewMemberInvite(groupId: UUID, username: String? = nil, email: String? = nil) async throws -> MemberPreviewResponse {
        let request = MemberPreviewRequest(username: username, email: email)
        return try await apiClient.request(APIRequest(
            path: "groups/\(groupId.uuidString)/members/preview",
            method: "POST",
            body: request
        ))
    }

    func getUserMembership(in groupId: UUID) -> Membership? {
        guard let userId = user?.id else { return nil }
        return membershipsByGroupId[groupId]?.first { $0.userId == userId }
    }

    // MARK: - Expenses / Balances
    func loadExpenses(groupId: UUID) async throws {
        isLoadingExpenses = true
        defer { isLoadingExpenses = false }
        let expenses: [Expense] = try await apiClient.request(APIRequest(
            path: "groups/\(groupId.uuidString)/expenses"
        ))
        expensesByGroupId[groupId] = expenses
    }

    func createExpense(groupId: UUID, request: CreateExpenseRequest) async throws -> Expense {
        isLoading = true
        defer { isLoading = false }
        let expense: Expense = try await apiClient.request(APIRequest(
            path: "groups/\(groupId.uuidString)/expenses",
            method: "POST",
            body: request
        ))
        var current = expensesByGroupId[groupId] ?? []
        current.insert(expense, at: 0)
        expensesByGroupId[groupId] = current
        async let _ = loadExpenses(groupId: groupId)
        async let _ = loadBalances(groupId: groupId)
        return expense
    }

    func loadBalances(groupId: UUID) async throws {
        isLoadingBalances = true
        defer { isLoadingBalances = false }
        do {
            let batch: SettlementBatch = try await apiClient.request(APIRequest(
                path: "groups/\(groupId.uuidString)/settlements/latest"
            ))
            settlementsByGroupId[groupId] = batch.settlements ?? []
        } catch APIError.server(let status, _) where status == 404 {
            settlementsByGroupId[groupId] = []
        }
    }

    func expenses(for groupId: UUID) -> [Expense] {
        expensesByGroupId[groupId] ?? []
    }

    func settlements(for groupId: UUID) -> [Settlement] {
        settlementsByGroupId[groupId] ?? []
    }

    // MARK: - Shopping Sessions
    func loadShoppingSessions(groupId: UUID) async throws {
        isLoadingShopping = true
        defer { isLoadingShopping = false }
        let sessions = try await shoppingService.listSessions(groupId: groupId)
        shoppingSessionsByGroupId[groupId] = sessions
    }

    func createShoppingSession(groupId: UUID, request: ShoppingSessionCreate) async throws -> ShoppingSession {
        let session = try await shoppingService.createSession(groupId: groupId, request: request)
        var sessions = shoppingSessionsByGroupId[groupId] ?? []
        sessions.insert(session, at: 0)
        shoppingSessionsByGroupId[groupId] = sessions
        return session
    }

    func deleteShoppingSession(sessionId: UUID, groupId: UUID) async throws -> ShoppingSession {
        let deleted: ShoppingSession = try await apiClient.request(APIRequest(
            path: "shopping-sessions/\(sessionId.uuidString)",
            method: "DELETE"
        ))
        if var sessions = shoppingSessionsByGroupId[groupId] {
            sessions.removeAll { $0.id == sessionId }
            shoppingSessionsByGroupId[groupId] = sessions
        }
        return deleted
    }

    func refreshShoppingSession(sessionId: UUID, groupId: UUID) async throws -> ShoppingSession {
        let session = try await shoppingService.getSession(sessionId: sessionId)
        if var sessions = shoppingSessionsByGroupId[groupId],
           let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index] = session
            shoppingSessionsByGroupId[groupId] = sessions
        }
        return session
    }

    func setParticipants(sessionId: UUID, groupId: UUID, membershipIds: [UUID]) async throws -> ShoppingSession {
        let request = ParticipantSetRequest(participantMembershipIds: membershipIds)
        let session = try await shoppingService.setParticipants(sessionId: sessionId, request: request)
        if var sessions = shoppingSessionsByGroupId[groupId],
           let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index] = session
            shoppingSessionsByGroupId[groupId] = sessions
        }
        return session
    }

    // MARK: - Items
    func addItemToSession(
        sessionId: UUID,
        groupId: UUID,
        name: String,
        priceDouble: Double,
        quantity: Int
    ) async throws -> ShoppingSession {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, priceDouble > 0, quantity >= 1 else {
            throw AppStateError.invalidItemInput
        }

        let totalCents = Int((priceDouble * Double(quantity) * 100.0).rounded())
        let request = ShoppingItemCreate(
            name: trimmedName,
            quantity: quantity,
            unitPriceCents: nil,
            totalCents: totalCents
        )

        _ = try await shoppingService.createItem(sessionId: sessionId, request: request)
        return try await refreshShoppingSession(sessionId: sessionId, groupId: groupId)
    }

    func createShoppingItem(
        sessionId: UUID,
        groupId: UUID,
        request: ShoppingItemCreate
    ) async throws -> ShoppingItem {
        let item = try await shoppingService.createItem(sessionId: sessionId, request: request)
        _ = try await refreshShoppingSession(sessionId: sessionId, groupId: groupId)
        return item
    }

    func updateShoppingItem(
        itemId: UUID,
        sessionId: UUID,
        groupId: UUID,
        request: ShoppingItemCreate,
        membershipIds: [UUID]
    ) async throws -> ShoppingItem {
        guard !membershipIds.isEmpty else { throw AppStateError.invalidParticipants }
        let item: ShoppingItem = try await apiClient.request(APIRequest(
            path: "items/\(itemId.uuidString)",
            method: "PATCH",
            body: request
        ))
        _ = try await shoppingService.setSharers(itemId: itemId, request: SharersSetRequest(membershipIds: membershipIds))
        _ = try await refreshShoppingSession(sessionId: sessionId, groupId: groupId)
        return item
    }

    func deleteShoppingItem(itemId: UUID, sessionId: UUID, groupId: UUID) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await apiClient.request(APIRequest(
            path: "items/\(itemId.uuidString)",
            method: "DELETE"
        ))
        _ = try await refreshShoppingSession(sessionId: sessionId, groupId: groupId)
    }

    func setSharers(itemId: UUID, membershipIds: [UUID]) async throws {
        _ = try await shoppingService.setSharers(itemId: itemId, request: SharersSetRequest(membershipIds: membershipIds))
    }

    // MARK: - Receipts
    func uploadReceipt(sessionId: UUID, groupId: UUID, imageData: Data, contentType: String = "image/jpeg") async throws -> ReceiptUpload {
        let receipt = try await shoppingService.uploadReceipt(sessionId: sessionId, imageData: imageData, contentType: contentType)
        _ = try await refreshShoppingSession(sessionId: sessionId, groupId: groupId)
        return receipt
    }

    func getReceiptDownloadURL(receiptUploadId: UUID) async throws -> String {
        let response = try await shoppingService.getReceiptDownloadURL(receiptUploadId: receiptUploadId)
        return response.url
    }

    func deleteReceipt(receiptUploadId: UUID) async throws {
        _ = try await shoppingService.deleteReceipt(receiptUploadId: receiptUploadId)
    }

    func extractReceiptItems(receiptUploadId: UUID) async throws -> [ReceiptExtractedItem] {
        try await shoppingService.extractReceiptItems(receiptUploadId: receiptUploadId)
    }
}

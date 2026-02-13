import Foundation
import Combine

enum AppStateError: Error {
    case invalidItemInput
    case invalidParticipants
}

@MainActor
public final class AppState: ObservableObject {
    // MARK: - Published state
    @Published var user: User?
    @Published var isLoading = false
    @Published var authError: String?

    @Published var groups: [Group] = []
    @Published var expensesByGroupId: [UUID: [Expense]] = [:]
    @Published var membershipsByGroupId: [UUID: [Membership]] = [:]
    @Published var settlementsByGroupId: [UUID: [Settlement]] = [:] // legacy snapshots
    @Published var groupBalancesByGroupId: [UUID: GroupBalances] = [:]
    @Published var settlementPaymentsByGroupId: [UUID: [SettlementPayment]] = [:]
    @Published var shoppingSessionsByGroupId: [UUID: [ShoppingSession]] = [:]
    @Published var isLoadingExpenses = false
    @Published var isLoadingBalances = false
    @Published var isLoadingShopping = false

    // MARK: - Dependencies
    let apiClient: APIClient
    let authService: AuthServicing
    let groupsService: GroupsServicing
    let shoppingService: ShoppingServicing
    let settlementService: SettlementServicing

    init(
        apiClient: APIClient = APIClient(),
        authService: AuthServicing? = nil,
        groupsService: GroupsServicing? = nil,
        shoppingService: ShoppingServicing? = nil,
        settlementService: SettlementServicing? = nil
    ) {
        self.apiClient = apiClient
        self.authService = authService ?? AuthService(client: apiClient)
        self.groupsService = groupsService ?? GroupsService(client: apiClient)
        self.shoppingService = shoppingService ?? ShoppingService(client: apiClient)
        self.settlementService = settlementService ?? SettlementService(client: apiClient)
    }

    // Public convenience initializer for app target; keeps designated initializer internal.
    public convenience init() {
        self.init(apiClient: APIClient())
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
        } catch {
            authError = "Session expired"
            user = nil
            await apiClient.clearTokens()
            return
        }

        do {
            try await loadGroups()
        } catch {
            // Keep authenticated session even if groups endpoint is temporarily unavailable.
            groups = []
            authError = "Logged in, but failed to load groups."
            print("⚠️ Failed to load groups during bootstrap: \(error)")
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
        do {
            try await loadGroups()
        } catch {
            // Authentication succeeded; do not fail login for secondary data fetches.
            groups = []
            authError = "Logged in, but failed to load groups."
            print("⚠️ Failed to load groups after login: \(error)")
        }
    }

    func signup(
        username: String,
        email: String,
        password: String,
        firstName: String,
        lastName: String
    ) async throws {
        isLoading = true
        defer { isLoading = false }
        let (tokens, me) = try await authService.signup(
            username: username,
            email: email,
            password: password,
            firstName: firstName,
            lastName: lastName
        )
        await apiClient.store(tokens: tokens)
        user = me
        do {
            try await loadGroups()
        } catch {
            groups = []
            authError = "Account created, but failed to load groups."
            print("⚠️ Failed to load groups after signup: \(error)")
        }
    }

    func logout() async {
        user = nil
        groups = []
        expensesByGroupId = [:]
        membershipsByGroupId = [:]
        settlementsByGroupId = [:]
        groupBalancesByGroupId = [:]
        settlementPaymentsByGroupId = [:]
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

        if let existingIndex = groups.firstIndex(where: { $0.id == group.id }) {
            groups[existingIndex] = group
        } else {
            groups.insert(group, at: 0)
        }

        // Keep create flow snappy; reconcile canonical ordering/fields in background.
        Task { [weak self] in
            guard let self else { return }
            try? await self.loadMembers(groupId: group.id)
            try? await self.loadGroups()
        }

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
        groupBalancesByGroupId[groupId] = nil
        settlementPaymentsByGroupId[groupId] = nil
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
        let balances = try await settlementService.getBalances(groupId: groupId)
        groupBalancesByGroupId[groupId] = balances
    }

    func expenses(for groupId: UUID) -> [Expense] {
        expensesByGroupId[groupId] ?? []
    }

    func settlements(for groupId: UUID) -> [Settlement] {
        settlementsByGroupId[groupId] ?? []
    }

    func balances(for groupId: UUID) -> GroupBalances? {
        groupBalancesByGroupId[groupId]
    }

    func netBalanceCents(groupId: UUID, membershipId: UUID) -> Int {
        guard let balanceRows = groupBalancesByGroupId[groupId]?.balances else { return 0 }
        return balanceRows.first(where: { $0.membershipId == membershipId })?.netCents ?? 0
    }

    func loadSettlementPayments(groupId: UUID) async throws {
        let payments = try await settlementService.listPayments(groupId: groupId)
        settlementPaymentsByGroupId[groupId] = payments
    }

    func settlementPayments(for groupId: UUID) -> [SettlementPayment] {
        settlementPaymentsByGroupId[groupId] ?? []
    }

    @discardableResult
    func createSettlementPayment(
        groupId: UUID,
        request: SettlementPaymentCreateRequest
    ) async throws -> SettlementPayment {
        let payment = try await settlementService.createPayment(groupId: groupId, request: request)
        try await loadBalances(groupId: groupId)
        try await loadSettlementPayments(groupId: groupId)
        return payment
    }

    @discardableResult
    func confirmSettlementPayment(
        groupId: UUID,
        paymentId: UUID
    ) async throws -> SettlementPayment {
        let payment = try await settlementService.confirmPayment(paymentId: paymentId)
        try await loadBalances(groupId: groupId)
        try await loadSettlementPayments(groupId: groupId)
        return payment
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
        let item: ShoppingItem = try await apiClient.request(APIRequest(
            path: "items/\(itemId.uuidString)",
            method: "PATCH",
            body: request
        ))
        if !membershipIds.isEmpty {
            _ = try await shoppingService.setSharers(itemId: itemId, request: SharersSetRequest(membershipIds: membershipIds))
        }
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

import Foundation

enum AppStateError: Error {
    case invalidItemInput
}

@MainActor
final class AppState: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var authError: String?

    let apiClient: APIClient
    let authService: AuthService
    let groupsService: GroupsService
    let shoppingService: ShoppingService

    init() {
        let client = APIClient()
        self.apiClient = client
        self.authService = AuthService(client: client)
        self.groupsService = GroupsService(client: client)
        self.shoppingService = ShoppingService(client: client)
    }

    func bootstrap() async {
        guard await apiClient.currentTokens() != nil else { return }
        await verifySession()
    }

    func verifySession() async {
        isLoading = true
        defer { isLoading = false }
        do {
            user = try await authService.me()
        } catch {
            authError = "Session expired"
            user = nil
            await apiClient.clearTokens()
        }
    }

    func logout() async {
        user = nil
        await apiClient.clearTokens()
    }

    func refreshShoppingSession(sessionId: UUID, groupId: UUID) async throws -> ShoppingSession {
        _ = groupId
        return try await shoppingService.getSession(sessionId: sessionId)
    }

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
    
    func getReceiptDownloadURL(receiptUploadId: UUID) async throws -> String {
        print("[AppState] Getting receipt download URL for: \(receiptUploadId)")
        do {
            let response = try await shoppingService.getReceiptDownloadURL(receiptUploadId: receiptUploadId)
            print("[AppState] ✅ Received download URL response")
            print("[AppState] URL: \(response.url)")
            print("[AppState] Expires in: \(response.expiresInSeconds) seconds")
            return response.url
        } catch {
            print("[AppState] ❌ Failed to get receipt download URL: \(error)")
            throw error
        }
    }

    func deleteReceipt(receiptUploadId: UUID) async throws {
        print("[AppState] Deleting receipt: \(receiptUploadId)")
        _ = try await shoppingService.deleteReceipt(receiptUploadId: receiptUploadId)
    }
}

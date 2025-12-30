import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var authError: String?

    let apiClient: APIClient
    let authService: AuthService
    let groupsService: GroupsService

    init() {
        let client = APIClient()
        self.apiClient = client
        self.authService = AuthService(client: client)
        self.groupsService = GroupsService(client: client)
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
}

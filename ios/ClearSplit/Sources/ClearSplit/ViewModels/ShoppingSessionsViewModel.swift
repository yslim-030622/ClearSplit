import Foundation
import Combine

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
            sessions = try await appState.shoppingService.listSessions(groupId: groupId)
        } catch {
            errorMessage = "Failed to load shopping sessions."
        }
    }
}


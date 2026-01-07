import Foundation
import Combine

@MainActor
final class CreateShoppingSessionViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var shoppingDate: Date = Date()
    @Published var useDate: Bool = true
    @Published var isCreating = false
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
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    func createSession() async -> ShoppingSession? {
        guard canCreate else { return nil }
        
        isCreating = true
        defer { isCreating = false }
        errorMessage = nil
        
        do {
            let request = ShoppingSessionCreate(
                title: title.trimmingCharacters(in: .whitespaces),
                shoppingDate: useDate ? shoppingDate : nil,
                paidBy: paidByMembershipId
            )
            return try await appState.shoppingService.createSession(groupId: groupId, request: request)
        } catch {
            errorMessage = "Failed to create shopping session."
            return nil
        }
    }
}


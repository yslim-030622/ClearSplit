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
            try await appState.loadShoppingSessions(groupId: groupId)
            var loadedSessions = appState.shoppingSessionsByGroupId[groupId] ?? []
            // Keep newest sessions first for predictable UX.
            loadedSessions.sort { lhs, rhs in
                let lhsDate = parseDateString(lhs.shoppingDate) ?? lhs.createdAt
                let rhsDate = parseDateString(rhs.shoppingDate) ?? rhs.createdAt
                return lhsDate > rhsDate
            }
            sessions = loadedSessions
        } catch let apiError as APIError {
            switch apiError {
            case .decoding:
                errorMessage = "Failed to load shopping sessions (response format mismatch)."
            case .server(let status, let message):
                errorMessage = message ?? "Server error (\(status)) while loading shopping sessions."
            case .network(let error):
                errorMessage = "Network error: \(error.localizedDescription)"
            case .unauthorized:
                errorMessage = "Session expired. Please log in again."
            }
        } catch {
            errorMessage = "Failed to load shopping sessions: \(error.localizedDescription)"
        }
    }

    func delete(session: ShoppingSession) async {
        do {
            _ = try await appState.deleteShoppingSession(sessionId: session.id, groupId: groupId)
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = "Failed to delete shopping session."
        }
    }

    private func parseDateString(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

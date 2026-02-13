import Foundation
import Combine

@MainActor
final class GroupsViewModel: ObservableObject {
    @Published var groups: [Group] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            groups = try await appState.groupsService.listGroups()
            for group in groups {
                try? await appState.loadBalances(groupId: group.id)
            }
        } catch {
            errorMessage = "Failed to load groups."
        }
    }
}

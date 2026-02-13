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
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            groups = try await appState.groupsService.listGroups()
            prefetchMemberCountsIfNeeded(for: groups)
        } catch where isCancellationError(error) {
            // Pull-to-refresh can cancel in-flight work; do not surface as user-facing failure.
            return
        } catch {
            errorMessage = "Failed to load groups."
        }
    }

    func delete(group: Group) async {
        let existingGroups = groups
        groups.removeAll { $0.id == group.id }

        do {
            try await appState.deleteGroup(groupId: group.id)
            errorMessage = nil
        } catch where isCancellationError(error) {
            groups = existingGroups
        } catch let APIError.server(_, message) {
            groups = existingGroups
            if let message, !message.isEmpty {
                errorMessage = message
            } else {
                errorMessage = "Failed to delete group."
            }
        } catch {
            groups = existingGroups
            errorMessage = "Failed to delete group."
        }
    }

    private func prefetchMemberCountsIfNeeded(for groups: [Group]) {
        let groupIdsToLoad = groups
            .map(\.id)
            .filter { appState.membershipsByGroupId[$0] == nil }

        guard !groupIdsToLoad.isEmpty else { return }

        for groupId in groupIdsToLoad {
            Task {
                try? await appState.loadMembers(groupId: groupId)
            }
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        if let apiError = error as? APIError,
           case .network(let underlyingError) = apiError {
            if underlyingError is CancellationError {
                return true
            }
            if let urlError = underlyingError as? URLError, urlError.code == .cancelled {
                return true
            }

            let nsError = underlyingError as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

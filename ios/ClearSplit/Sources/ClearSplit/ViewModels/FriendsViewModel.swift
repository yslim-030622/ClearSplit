import Foundation
import Combine

@MainActor
final class FriendsViewModel: ObservableObject {
    @Published var friends: [Friendship] = []
    @Published var incomingRequests: [Friendship] = []
    @Published var outgoingRequests: [Friendship] = []
    @Published private(set) var groupsInCommonByUserId: [UUID: Int] = [:]
    @Published var isLoading = false
    @Published var isSubmittingRequest = false
    @Published var errorMessage: String?

    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        observeGroupMembershipUpdates()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await refreshLists()
        } catch where isCancellationError(error) {
            return
        } catch {
            errorMessage = readableErrorMessage(from: error, fallback: "Failed to load friends.")
        }
    }

    func sendFriendRequest(input: String) async -> Bool {
        guard !isSubmittingRequest else { return false }

        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return false }

        isSubmittingRequest = true
        defer { isSubmittingRequest = false }

        do {
            _ = try await appState.friendsService.sendFriendRequest(
                toUserID: nil,
                identifier: trimmedInput
            )
            try await refreshLists()
            return true
        } catch where isCancellationError(error) {
            return false
        } catch {
            errorMessage = readableErrorMessage(from: error, fallback: "Failed to send friend request.")
            return false
        }
    }

    func acceptFriendRequest(friendshipID: UUID) async -> Bool {
        do {
            _ = try await appState.friendsService.acceptFriendRequest(friendshipID: friendshipID)
            try await refreshLists()
            return true
        } catch where isCancellationError(error) {
            return false
        } catch {
            errorMessage = readableErrorMessage(from: error, fallback: "Failed to accept friend request.")
            return false
        }
    }

    func declineFriendRequest(friendshipID: UUID) async -> Bool {
        do {
            _ = try await appState.friendsService.declineFriendRequest(friendshipID: friendshipID)
            try await refreshLists()
            return true
        } catch where isCancellationError(error) {
            return false
        } catch {
            errorMessage = readableErrorMessage(from: error, fallback: "Failed to decline friend request.")
            return false
        }
    }

    func removeFriend(friendshipID: UUID) async -> Bool {
        do {
            _ = try await appState.friendsService.removeFriendship(friendshipID: friendshipID)
            try await refreshLists()
            return true
        } catch where isCancellationError(error) {
            return false
        } catch {
            errorMessage = readableErrorMessage(from: error, fallback: "Failed to remove friend.")
            return false
        }
    }

    private func refreshLists() async throws {
        async let accepted = appState.friendsService.listFriends()
        async let incoming = appState.friendsService.listIncomingRequests()
        async let outgoing = appState.friendsService.listOutgoingRequests()
        let (acceptedList, incomingList, outgoingList) = try await (accepted, incoming, outgoing)

        friends = acceptedList.sorted {
            $0.friend.displayName.localizedCaseInsensitiveCompare($1.friend.displayName) == .orderedAscending
        }
        incomingRequests = incomingList.sorted { $0.createdAt > $1.createdAt }
        outgoingRequests = outgoingList.sorted { $0.createdAt > $1.createdAt }
        recomputeGroupsInCommon()
        await loadGroupMembershipsForCommonCounts()
        recomputeGroupsInCommon()
    }

    private func observeGroupMembershipUpdates() {
        Publishers.CombineLatest(appState.$groups, appState.$membershipsByGroupId)
            .sink { [weak self] _, _ in
                self?.recomputeGroupsInCommon()
            }
            .store(in: &cancellables)
    }

    private func loadGroupMembershipsForCommonCounts() async {
        guard !friends.isEmpty else {
            groupsInCommonByUserId = [:]
            return
        }

        do {
            try await appState.loadGroups()
        } catch where isCancellationError(error) {
            return
        } catch {
            return
        }

        for group in appState.groups where appState.membershipsByGroupId[group.id] == nil {
            do {
                try await appState.loadMembers(groupId: group.id)
            } catch where isCancellationError(error) {
                return
            } catch {
                continue
            }
        }
    }

    private func recomputeGroupsInCommon() {
        let friendUserIds = Set(friends.map(\.friend.id))
        groupsInCommonByUserId = Self.computeGroupsInCommon(
            friendUserIds: friendUserIds,
            groups: appState.groups,
            membershipsByGroupId: appState.membershipsByGroupId
        )
    }

    nonisolated static func computeGroupsInCommon(
        friendUserIds: Set<UUID>,
        groups: [Group],
        membershipsByGroupId: [UUID: [Membership]]
    ) -> [UUID: Int] {
        guard !friendUserIds.isEmpty else { return [:] }

        var counts = Dictionary(uniqueKeysWithValues: friendUserIds.map { ($0, 0) })

        for group in groups {
            guard let memberships = membershipsByGroupId[group.id] else { continue }
            let memberUserIds = Set(memberships.map(\.userId))
            for friendUserId in friendUserIds where memberUserIds.contains(friendUserId) {
                counts[friendUserId, default: 0] += 1
            }
        }

        return counts
    }

    private func readableErrorMessage(from error: Error, fallback: String) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .server(_, let message):
                if let message, !message.isEmpty {
                    return message
                }
                return fallback
            case .unauthorized:
                return "Your session expired. Please log in again."
            case .decoding:
                return "Unexpected server response. Please try again."
            case .network(let underlyingError):
                return "Network error: \(underlyingError.localizedDescription)"
            }
        }
        return fallback
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

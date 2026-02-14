import Foundation

protocol FriendsServicing {
    func listFriends() async throws -> [Friendship]
    func listIncomingRequests() async throws -> [Friendship]
    func listOutgoingRequests() async throws -> [Friendship]
    func sendFriendRequest(toUserID: UUID?, identifier: String?) async throws -> Friendship
    func acceptFriendRequest(friendshipID: UUID) async throws -> Friendship
    func declineFriendRequest(friendshipID: UUID) async throws -> Friendship
    func removeFriendship(friendshipID: UUID) async throws -> Friendship
}

private struct FriendRequestCreateBody: Encodable {
    let toUserId: UUID?
    let identifier: String?
}

final class FriendsService: FriendsServicing {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func listFriends() async throws -> [Friendship] {
        try await client.request(APIRequest(path: "friends"))
    }

    func listIncomingRequests() async throws -> [Friendship] {
        try await client.request(APIRequest(path: "friends/requests/incoming"))
    }

    func listOutgoingRequests() async throws -> [Friendship] {
        try await client.request(APIRequest(path: "friends/requests/outgoing"))
    }

    func sendFriendRequest(toUserID: UUID?, identifier: String?) async throws -> Friendship {
        try await client.request(APIRequest(
            path: "friends/requests",
            method: "POST",
            body: FriendRequestCreateBody(toUserId: toUserID, identifier: identifier)
        ))
    }

    func acceptFriendRequest(friendshipID: UUID) async throws -> Friendship {
        try await client.request(APIRequest(
            path: "friends/requests/\(friendshipID.uuidString)/accept",
            method: "POST"
        ))
    }

    func declineFriendRequest(friendshipID: UUID) async throws -> Friendship {
        try await client.request(APIRequest(
            path: "friends/requests/\(friendshipID.uuidString)/decline",
            method: "POST"
        ))
    }

    func removeFriendship(friendshipID: UUID) async throws -> Friendship {
        try await client.request(APIRequest(
            path: "friends/\(friendshipID.uuidString)",
            method: "DELETE"
        ))
    }
}

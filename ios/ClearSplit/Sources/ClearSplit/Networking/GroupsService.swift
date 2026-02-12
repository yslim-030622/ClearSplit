import Foundation

protocol GroupsServicing {
    func listGroups() async throws -> [Group]
}

final class GroupsService: GroupsServicing {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func listGroups() async throws -> [Group] {
        try await client.request(APIRequest<[Group]>(path: "groups"))
    }
}

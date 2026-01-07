import Foundation

protocol GroupsServicing {
    func listGroups() async throws -> [CSGroup]
}

final class GroupsService: GroupsServicing {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func listGroups() async throws -> [CSGroup] {
        try await client.request(APIRequest<[CSGroup]>(path: "groups"))
    }
}

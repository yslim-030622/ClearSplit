import Foundation

enum FriendshipStatus: String, Codable {
    case pending
    case accepted
    case declined
}

struct FriendUser: Codable, Equatable, Identifiable {
    let id: UUID
    let username: String
    let firstName: String
    let lastName: String
}

extension FriendUser {
    var displayName: String {
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        if !fullName.isEmpty {
            return fullName
        }
        return username
    }

    var handle: String {
        "@\(username)"
    }
}

struct Friendship: Codable, Equatable, Identifiable {
    let id: UUID
    let requestedByUserId: UUID
    let status: FriendshipStatus
    let createdAt: Date
    let updatedAt: Date
    let friend: FriendUser
}

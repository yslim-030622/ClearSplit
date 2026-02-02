import Foundation

// MARK: - Group

public struct Group: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let name: String
    public let currency: String
    public let createdAt: Date
    public let updatedAt: Date
    public let version: Int
    public let userMembershipId: UUID?  // Current user's membership in this group
}

// MARK: - Membership

public struct Membership: Codable, Identifiable {
    public let id: UUID
    public let groupId: UUID
    public let userId: UUID
    public let role: String
    public let createdAt: Date
    public let user: User?  // Embedded user info
}

public extension Membership {
    var displayName: String {
        if let email = user?.email {
            return email.components(separatedBy: "@").first ?? email
        }
        return String(userId.uuidString.prefix(8)) + "..."
    }
}

// MARK: - Member Preview

public struct MemberPreviewRequest: Codable {
    public let username: String?
    public let email: String?
    
    public init(username: String? = nil, email: String? = nil) {
        self.username = username
        self.email = email
    }
}

public struct MemberPreviewResponse: Codable {
    public let found: Bool
    public let alreadyMember: Bool?
    public let user: User?
    public let membershipId: UUID?
    public let role: String?
}

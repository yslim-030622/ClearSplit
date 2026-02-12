import Foundation

// MARK: - Auth Tokens

public struct AuthTokens: Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String
}

// MARK: - User

public struct User: Codable, Equatable, Identifiable {
    public let id: UUID
    public let username: String
    public let email: String
    public let firstName: String
    public let lastName: String

    public init(
        id: UUID,
        username: String,
        email: String,
        firstName: String = "",
        lastName: String = ""
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case firstName
        case lastName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        username = try container.decodeIfPresent(String.self, forKey: .username)
            ?? email.components(separatedBy: "@").first
            ?? "user"
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
    }
}

public extension User {
    var displayName: String {
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        if !fullName.isEmpty {
            return fullName
        }
        return email.components(separatedBy: "@").first ?? username
    }
    
    var initials: String {
        let firstInitial = firstName.first.map(String.init) ?? ""
        let lastInitial = lastName.first.map(String.init) ?? ""
        let combined = (firstInitial + lastInitial).uppercased()
        if !combined.isEmpty {
            return combined
        }
        return username.prefix(2).uppercased()
    }
}

// MARK: - Auth Requests

struct LoginRequest: Codable {
    let identifier: String
    let password: String
}

struct SignupRequest: Codable {
    let username: String
    let email: String
    let password: String
    let firstName: String
    let lastName: String
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let user: User?

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case tokenType
        case user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType) ?? "bearer"
        user = try? container.decodeIfPresent(User.self, forKey: .user)
    }
}

struct RefreshTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let refreshToken: String?
}

struct RefreshRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken
    }
}

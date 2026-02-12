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

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case user
    }
}

struct RefreshRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

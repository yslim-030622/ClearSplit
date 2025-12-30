//
//  Models.swift
//  ClearSplit
//

import Foundation

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let user: User
}

struct User: Codable, Identifiable {
    let id: UUID
    let email: String
}

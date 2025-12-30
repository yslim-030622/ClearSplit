//
//  AuthService.swift
//  ClearSplit
//

import Foundation

enum AuthService {
    struct LoginRequest: Encodable { let email: String; let password: String }
    struct SignupRequest: Encodable { let email: String; let password: String }

    static func login(email: String, password: String) async throws -> AuthTokens {
        let req = LoginRequest(email: email, password: password)
        return try await APIClient.shared.request(
            "/auth/login",
            method: "POST",
            body: req,
            requiresAuth: false
        )
    }

    static func signup(email: String, password: String) async throws -> AuthTokens {
        let req = SignupRequest(email: email, password: password)
        // Signup returns TokenResponse (AuthTokens), not just User.
        return try await APIClient.shared.request(
            "/auth/signup",
            method: "POST",
            body: req,
            requiresAuth: false
        )
    }

    static func me() async throws -> User {
        try await APIClient.shared.request("/auth/me")
    }

    static func logout() {
        KeychainService.deleteTokens()
    }
}


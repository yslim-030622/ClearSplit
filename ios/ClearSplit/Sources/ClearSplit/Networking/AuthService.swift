import Foundation

protocol AuthServicing {
    func login(identifier: String, password: String) async throws -> (AuthTokens, User)
    func refresh() async throws -> AuthTokens
    func me() async throws -> User
    func signup(email: String, password: String) async throws -> AuthTokens
}

final class AuthService: AuthServicing {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func login(identifier: String, password: String) async throws -> (AuthTokens, User) {
        let request = APIRequest<TokenResponse>(
            path: "auth/login",
            method: "POST",
            body: LoginRequest(identifier: identifier, password: password),
            requiresAuth: false
        )
        let response: TokenResponse = try await client.request(request)
        let tokens = AuthTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
        await client.store(tokens: tokens)
        return (tokens, response.user)
    }

    func refresh() async throws -> AuthTokens {
        guard let tokens = await client.currentTokens() else { throw APIError.unauthorized }
        let newTokens: TokenResponse = try await client.request(
            APIRequest<TokenResponse>(
                path: "auth/refresh",
                method: "POST",
                body: RefreshRequest(refreshToken: tokens.refreshToken),
                requiresAuth: false
            )
        )
        let refreshed = AuthTokens(accessToken: newTokens.accessToken, refreshToken: newTokens.refreshToken)
        await client.store(tokens: refreshed)
        return refreshed
    }

    func signup(email: String, password: String) async throws -> AuthTokens {
        // Create account
        let signupRequest = APIRequest<TokenResponse>(
            path: "auth/signup",
            method: "POST",
            body: LoginRequest(email: email, password: password),
            requiresAuth: false
        )
        let _: TokenResponse = try await client.request(signupRequest)

        // Auto-login after signup
        let tokens = try await login(identifier: email, password: password).0
        return tokens
    }

    func me() async throws -> User {
        try await client.request(APIRequest<User>(path: "auth/me"))
    }
}

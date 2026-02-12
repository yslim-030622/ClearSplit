import Foundation

protocol AuthServicing {
    func login(identifier: String, password: String) async throws -> (AuthTokens, User)
    func refresh() async throws -> AuthTokens
    func me() async throws -> User
    func signup(
        username: String,
        email: String,
        password: String,
        firstName: String,
        lastName: String
    ) async throws -> (AuthTokens, User)
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
        let tokens = AuthTokens(accessToken: response.accessToken, refreshToken: response.refreshToken, tokenType: response.tokenType)
        await client.store(tokens: tokens)
        // Support both response shapes:
        // 1) login returns tokens + user
        // 2) login returns tokens only, then fetch user via /auth/me
        if let user = response.user {
            return (tokens, user)
        }
        let user = try await me()
        return (tokens, user)
    }

    func refresh() async throws -> AuthTokens {
        guard let tokens = await client.currentTokens() else { throw APIError.unauthorized }
        let newTokens: RefreshTokenResponse = try await client.request(
            APIRequest<RefreshTokenResponse>(
                path: "auth/refresh",
                method: "POST",
                body: RefreshRequest(refreshToken: tokens.refreshToken),
                requiresAuth: false
            )
        )
        let refreshed = AuthTokens(
            accessToken: newTokens.accessToken,
            refreshToken: newTokens.refreshToken ?? tokens.refreshToken,
            tokenType: newTokens.tokenType
        )
        await client.store(tokens: refreshed)
        return refreshed
    }

    func signup(
        username: String,
        email: String,
        password: String,
        firstName: String,
        lastName: String
    ) async throws -> (AuthTokens, User) {
        let signupRequest = APIRequest<TokenResponse>(
            path: "auth/signup",
            method: "POST",
            body: SignupRequest(
                username: username,
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName
            ),
            requiresAuth: false
        )
        let response: TokenResponse = try await client.request(signupRequest)
        let tokens = AuthTokens(accessToken: response.accessToken, refreshToken: response.refreshToken, tokenType: response.tokenType)
        await client.store(tokens: tokens)
        if let user = response.user {
            return (tokens, user)
        }
        let user = try await me()
        return (tokens, user)
    }

    func me() async throws -> User {
        try await client.request(APIRequest<User>(path: "auth/me"))
    }
}

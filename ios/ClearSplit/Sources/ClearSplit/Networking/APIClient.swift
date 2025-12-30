import Foundation

enum APIError: Error {
    case unauthorized
    case decoding
    case server(status: Int, message: String?)
    case network(Error)
}

actor AuthCoordinator {
    private(set) var tokens: AuthTokens?
    private var refreshTask: Task<AuthTokens, Error>?
    private let store: TokenStoring

    init(store: TokenStoring) {
        self.store = store
        self.tokens = store.loadTokens()
    }

    func setTokens(_ tokens: AuthTokens) async throws {
        self.tokens = tokens
        try store.save(tokens: tokens)
    }

    func clear() async throws {
        tokens = nil
        try store.clear()
    }

    func getTokens() -> AuthTokens? {
        tokens
    }

    func refresh(
        using action: @escaping (AuthTokens) async throws -> AuthTokens
    ) async throws -> AuthTokens {
        if let task = refreshTask {
            return try await task.value
        }
        guard let current = tokens else { throw APIError.unauthorized }

        let task = Task { () -> AuthTokens in
            let fresh = try await action(current)
            try await setTokens(fresh)
            return fresh
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}

struct APIRequest {
    let path: String
    var method: String = "GET"
    var body: Encodable?
    var requiresAuth: Bool = true
}

final class APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let auth: AuthCoordinator

    init(
        baseURL: URL = APIConfig.baseURL,
        session: URLSession = .shared,
        tokenStore: TokenStoring = KeychainService()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.auth = AuthCoordinator(store: tokenStore)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func currentTokens() async -> AuthTokens? {
        await auth.getTokens()
    }

    func clearTokens() async {
        try? await auth.clear()
    }

    func store(tokens: AuthTokens) async {
        try? await auth.setTokens(tokens)
    }

    func request<T: Decodable>(_ apiRequest: APIRequest) async throws -> T {
        return try await perform(apiRequest, retryingOn401: true)
    }

    private func perform<T: Decodable>(_ apiRequest: APIRequest, retryingOn401: Bool) async throws -> T {
        var request = try await buildRequest(apiRequest)
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: "Invalid response")
        }

        if http.statusCode == 401, retryingOn401, apiRequest.requiresAuth {
            // attempt refresh once
            let refreshed = try await auth.refresh { current in
                try await self.refreshTokens(refreshToken: current.refreshToken)
            }
            request.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await session.data(for: request)
            return try decodeResponse(data: retryData, response: retryResponse)
        }

        return try decodeResponse(data: data, response: response)
    }

    private func decodeResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: "Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            // Debug logging (no secrets/tokens are in the body)
            print("🚨 API error status=\(http.statusCode) body=\(message ?? "nil")")
            throw APIError.server(status: http.statusCode, message: message)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func buildRequest(_ apiRequest: APIRequest) async throws -> URLRequest {
        let url = baseURL.appendingPathComponent(apiRequest.path)
        var request = URLRequest(url: url)
        request.httpMethod = apiRequest.method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = apiRequest.body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        if apiRequest.requiresAuth, let tokens = await auth.getTokens() {
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func refreshTokens(refreshToken: String) async throws -> AuthTokens {
        let request = APIRequest(
            path: "auth/refresh",
            method: "POST",
            body: RefreshRequest(refreshToken: refreshToken),
            requiresAuth: false
        )
        let response: TokenResponse = try await perform(request, retryingOn401: false)
        return AuthTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
    }
}

// Helper to encode arbitrary Encodable without exposing its concrete type
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        self.encodeFunc = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}

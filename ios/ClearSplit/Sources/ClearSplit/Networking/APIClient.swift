import Foundation

public enum APIError: Error {
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

struct APIRequest<T: Decodable> {
    let path: String
    var method: String = "GET"
    var body: Encodable?
    var requiresAuth: Bool = true
    var contentType: String?
    
    init(path: String, method: String = "GET", body: Encodable? = nil, requiresAuth: Bool = true) {
        self.path = path
        self.method = method
        self.body = body
        self.requiresAuth = requiresAuth
    }
}

final class APIClient {
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601WithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

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
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.parseDate(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(value)"
            )
        }
        decoder.keyDecodingStrategy = .convertFromSnakeCase
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

    func request<T: Decodable>(_ apiRequest: APIRequest<T>) async throws -> T {
        return try await perform(apiRequest, retryingOn401: true)
    }

    func createShoppingItem(sessionId: UUID, request: ShoppingItemCreate) async throws -> ShoppingItem {
        try await self.request(APIRequest(
            path: "shopping-sessions/\(sessionId.uuidString)/items",
            method: "POST",
            body: request
        ))
    }
    
    func upload<T: Decodable>(request: APIRequest<T>, body: Data) async throws -> T {
        return try await performUpload(request, body: body, retryingOn401: true)
    }

    private func perform<T: Decodable>(_ apiRequest: APIRequest<T>, retryingOn401: Bool) async throws -> T {
        var request = try await buildRequest(apiRequest)
        
        // Log receipt download URL requests
        if apiRequest.path.contains("/receipts/") && apiRequest.path.contains("/download-url") {
            print("[APIClient] 📥 Requesting receipt download URL: \(apiRequest.path)")
            print("[APIClient] Full URL: \(request.url?.absoluteString ?? "nil")")
            print("[APIClient] Method: \(apiRequest.method)")
            print("[APIClient] Requires auth: \(apiRequest.requiresAuth)")
            if let authHeader = request.value(forHTTPHeaderField: "Authorization") {
                let tokenPreview = authHeader.prefix(20) + "..."
                print("[APIClient] Auth header present: \(tokenPreview)")
            } else {
                print("[APIClient] ⚠️ No auth header found")
            }
        }
        
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if apiRequest.path.contains("/receipts/") && apiRequest.path.contains("/download-url") {
                print("[APIClient] ❌ Network error for receipt download URL: \(error)")
            }
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: "Invalid response")
        }

        if http.statusCode == 401, retryingOn401, apiRequest.requiresAuth {
            if apiRequest.path.contains("/receipts/") && apiRequest.path.contains("/download-url") {
                print("[APIClient] 🔄 Received 401, attempting token refresh for receipt download URL")
            }
            // attempt refresh once
            let refreshed = try await auth.refresh { current in
                try await self.refreshTokens(refreshToken: current.refreshToken)
            }
            request.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await session.data(for: request)
            return try decodeResponse(data: retryData, response: retryResponse, path: apiRequest.path)
        }

        return try decodeResponse(data: data, response: response, path: apiRequest.path)
    }

    private func decodeResponse<T: Decodable>(data: Data, response: URLResponse, path: String = "") throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: "Invalid response")
        }
        
        // Enhanced logging for receipt download URL endpoint
        let isReceiptDownload = path.contains("/receipts/") && path.contains("/download-url")
        
        if isReceiptDownload {
            print("[APIClient] 📥 Receipt download URL response - Status: \(http.statusCode)")
            print("[APIClient] Response headers: \(http.allHeaderFields)")
            if let responseBody = String(data: data, encoding: .utf8) {
                print("[APIClient] Response body: \(responseBody)")
            } else {
                print("[APIClient] Response body (binary): \(data.count) bytes")
            }
        }
        
        guard (200..<300).contains(http.statusCode) else {
            // Try to parse FastAPI error response format: {"detail": "error message"}
            var errorMessage: String?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                errorMessage = detail
            } else if let message = String(data: data, encoding: .utf8), !message.isEmpty {
                errorMessage = message
            }
            // Debug logging (no secrets/tokens are in the body)
            if isReceiptDownload {
                print("[APIClient] ❌ Receipt download URL error - Status: \(http.statusCode), Message: \(errorMessage ?? "nil")")
            } else {
                print("🚨 API error status=\(http.statusCode) message=\(errorMessage ?? "nil")")
            }
            throw APIError.server(status: http.statusCode, message: errorMessage)
        }
        
        do {
            let decoded = try decoder.decode(T.self, from: data)
            if isReceiptDownload {
                print("[APIClient] ✅ Successfully decoded ReceiptDownloadURLResponse")
                if let urlResponse = decoded as? ReceiptDownloadURLResponse {
                    print("[APIClient] URL: \(urlResponse.url)")
                    print("[APIClient] URL scheme: \(URL(string: urlResponse.url)?.scheme ?? "nil")")
                    print("[APIClient] Expires in: \(urlResponse.expiresInSeconds) seconds")
                }
            }
            return decoded
        } catch {
            if path == "auth/login" || path == "auth/me" || path == "groups" {
                print("[APIClient] ❌ Decoding failed for path=\(path): \(error)")
                if let object = try? JSONSerialization.jsonObject(with: data),
                   let dict = object as? [String: Any] {
                    print("[APIClient] Response keys: \(dict.keys.sorted())")
                    if let user = dict["user"] as? [String: Any] {
                        print("[APIClient] User keys: \(user.keys.sorted())")
                    }
                }
            }
            if isReceiptDownload {
                print("[APIClient] ❌ Failed to decode ReceiptDownloadURLResponse")
                print("[APIClient] Decoding error: \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[APIClient] Raw JSON: \(jsonString)")
                }
            }
            throw APIError.decoding
        }
    }

    private func performUpload<T: Decodable>(_ apiRequest: APIRequest<T>, body: Data, retryingOn401: Bool) async throws -> T {
        var request = try await buildUploadRequest(apiRequest, body: body)
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
            return try decodeResponse(data: retryData, response: retryResponse, path: apiRequest.path)
        }

        return try decodeResponse(data: data, response: response, path: apiRequest.path)
    }

    private func buildRequest<T: Decodable>(_ apiRequest: APIRequest<T>) async throws -> URLRequest {
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
    
    private func buildUploadRequest<T: Decodable>(_ apiRequest: APIRequest<T>, body: Data) async throws -> URLRequest {
        let url = baseURL.appendingPathComponent(apiRequest.path)
        var request = URLRequest(url: url)
        request.httpMethod = apiRequest.method
        
        if let contentType = apiRequest.contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        
        request.httpBody = body

        if apiRequest.requiresAuth, let tokens = await auth.getTokens() {
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func refreshTokens(refreshToken: String) async throws -> AuthTokens {
        let request = APIRequest<RefreshTokenResponse>(
            path: "auth/refresh",
            method: "POST",
            body: RefreshRequest(refreshToken: refreshToken),
            requiresAuth: false
        )
        let response: RefreshTokenResponse = try await perform(request, retryingOn401: false)
        return AuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            tokenType: response.tokenType
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = iso8601WithFractionalSeconds.date(from: value) ??
            iso8601WithoutFractionalSeconds.date(from: value) {
            return date
        }

        // FastAPI commonly emits microseconds and a numeric timezone offset.
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss",
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
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

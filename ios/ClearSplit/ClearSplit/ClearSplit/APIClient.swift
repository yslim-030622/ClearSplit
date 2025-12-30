//
//  APIClient.swift
//  ClearSplit
//

import Foundation

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private var refreshTask: Task<AuthTokens, Error>?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public request

    func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        var request = try buildRequest(endpoint, method: method, body: body, requiresAuth: requiresAuth)

        do {
            return try await performRequest(request)
        } catch APIError.unauthorized where requiresAuth {
            try await refreshTokens()
            request = try buildRequest(endpoint, method: method, body: body, requiresAuth: true)
            return try await performRequest(request)
        }
    }

    // MARK: - Request builders

    private func buildRequest(
        _ endpoint: String,
        method: String,
        body: Encodable?,
        requiresAuth: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: endpoint, relativeTo: APIConfig.baseURL) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth, let tokens = KeychainService.getTokens() {
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        return request
    }

    // MARK: - Execution

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            // Handle FastAPI/Pydantic datetime format (ISO8601 WITHOUT timezone suffix)
            decoder.dateDecodingStrategy = .custom({ decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                // Try ISO8601 with fractional seconds, no timezone (FastAPI default)
                let formatter1 = DateFormatter()
                formatter1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                formatter1.timeZone = TimeZone(secondsFromGMT: 0)
                if let date = formatter1.date(from: dateString) {
                    return date
                }
                
                // Try ISO8601 without fractional seconds, no timezone
                let formatter2 = DateFormatter()
                formatter2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                formatter2.timeZone = TimeZone(secondsFromGMT: 0)
                if let date = formatter2.date(from: dateString) {
                    return date
                }
                
                // Try ISO8601 with fractional seconds and Z
                let formatter3 = ISO8601DateFormatter()
                formatter3.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter3.date(from: dateString) {
                    return date
                }
                
                // Try standard ISO8601 with timezone
                let formatter4 = ISO8601DateFormatter()
                if let date = formatter4.date(from: dateString) {
                    return date
                }
                
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid date format: \(dateString)"
                )
            })

            switch httpResponse.statusCode {
            case 200 ... 299:
                #if DEBUG
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📥 Response (\(httpResponse.statusCode)): \(responseString)")
                }
                #endif
                
                do {
                    return try decoder.decode(T.self, from: data)
                } catch {
                    print("❌ Decoding Error: \(error)")
                    #if DEBUG
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("   Raw JSON: \(responseString)")
                    }
                    #endif
                    throw APIError.decodingError(error)
                }

            case 401:
                throw APIError.unauthorized
            
            case 422:
                let errorMsg = parseValidationError(from: data, decoder: decoder)
                throw APIError.validationError(errorMsg)

            default:
                let bodyString = String(data: data, encoding: .utf8) ?? "<no body>"
                print("❌ API error \(httpResponse.statusCode) body: \(bodyString)")
                let msg = (try? decoder.decode([String: String].self, from: data))?["detail"]
                throw APIError.serverError(httpResponse.statusCode, msg)
            }
        } catch let error as APIError {
            throw error
        } catch {
            if let urlError = error as? URLError {
                throw APIError.networkError(urlError)
            }
            throw APIError.unknown
        }
    }
    
    private func parseValidationError(from data: Data, decoder: JSONDecoder) -> String {
        struct ValidationErrorResponse: Decodable {
            let detail: [ValidationDetail]
        }
        struct ValidationDetail: Decodable {
            let loc: [String]
            let msg: String
        }
        
        if let errorResponse = try? decoder.decode(ValidationErrorResponse.self, from: data) {
            return errorResponse.detail.map { "\($0.loc.last?.capitalized ?? "Field"): \($0.msg)" }.joined(separator: "\n")
        }
        return "Invalid input format."
    }

    // MARK: - Token Refresh
    private func refreshTokens() async throws {
        if let existing = refreshTask { _ = try await existing.value; return }
        let task = Task<AuthTokens, Error> {
            guard let tokens = KeychainService.getTokens() else { throw APIError.unauthorized }
            struct RefreshRequest: Encodable { 
                let refreshToken: String 
                enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
            }
            let refreshReq = RefreshRequest(refreshToken: tokens.refreshToken)
            let newTokens: AuthTokens = try await performRequest(
                try buildRequest("/auth/refresh", method: "POST", body: refreshReq, requiresAuth: false)
            )
            try KeychainService.saveTokens(newTokens)
            return newTokens
        }
        refreshTask = task
        defer { refreshTask = nil }
        _ = try await task.value
    }
}

import Foundation

public struct HealthResponse: Codable, Equatable {
    public let status: String
}

public protocol HealthChecking {
    func fetchHealth() async throws -> HealthResponse
}

@available(macOS 12.0, iOS 15.0, *)
public struct HealthClient: HealthChecking {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://localhost:8000")!,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func fetchHealth() async throws -> HealthResponse {
        let url = baseURL.appendingPathComponent("health")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HealthResponse.self, from: data)
    }
}

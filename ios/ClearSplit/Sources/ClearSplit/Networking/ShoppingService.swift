import Foundation

protocol ShoppingServicing {
    func listSessions(groupId: UUID) async throws -> [ShoppingSession]
    func getSession(sessionId: UUID) async throws -> ShoppingSession
    func createSession(groupId: UUID, request: ShoppingSessionCreate) async throws -> ShoppingSession
    func setParticipants(sessionId: UUID, request: ParticipantSetRequest) async throws -> ShoppingSession
    func uploadReceipt(sessionId: UUID, imageData: Data, contentType: String) async throws -> ReceiptUpload
    func createItem(sessionId: UUID, request: ShoppingItemCreate) async throws -> ShoppingItem
    func setSharers(itemId: UUID, request: SharersSetRequest) async throws -> SharersSetResponse
}

final class ShoppingService: ShoppingServicing {
    private let client: APIClient
    
    init(client: APIClient) {
        self.client = client
    }
    
    // MARK: - Shopping Sessions
    
    func listSessions(groupId: UUID) async throws -> [ShoppingSession] {
        try await client.request(APIRequest(
            path: "groups/\(groupId.uuidString)/shopping-sessions"
        ))
    }
    
    func getSession(sessionId: UUID) async throws -> ShoppingSession {
        try await client.request(APIRequest(
            path: "shopping-sessions/\(sessionId.uuidString)"
        ))
    }
    
    func createSession(groupId: UUID, request: ShoppingSessionCreate) async throws -> ShoppingSession {
        try await client.request(APIRequest(
            path: "groups/\(groupId.uuidString)/shopping-sessions",
            method: .post,
            body: request
        ))
    }
    
    func setParticipants(sessionId: UUID, request: ParticipantSetRequest) async throws -> ShoppingSession {
        try await client.request(APIRequest(
            path: "shopping-sessions/\(sessionId.uuidString)/participants",
            method: .put,
            body: request
        ))
    }
    
    // MARK: - Receipts
    
    func uploadReceipt(sessionId: UUID, imageData: Data, contentType: String) async throws -> ReceiptUpload {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = createMultipartBody(
            boundary: boundary,
            imageData: imageData,
            contentType: contentType
        )
        
        var request = APIRequest<ReceiptUpload>(
            path: "shopping-sessions/\(sessionId.uuidString)/receipt",
            method: .post
        )
        request.contentType = "multipart/form-data; boundary=\(boundary)"
        
        return try await client.upload(request: request, body: body)
    }
    
    private func createMultipartBody(boundary: String, imageData: Data, contentType: String) -> Data {
        var body = Data()
        
        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"receipt.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
    // MARK: - Shopping Items
    
    func createItem(sessionId: UUID, request: ShoppingItemCreate) async throws -> ShoppingItem {
        try await client.createShoppingItem(sessionId: sessionId, request: request)
    }
    
    func setSharers(itemId: UUID, request: SharersSetRequest) async throws -> SharersSetResponse {
        try await client.request(APIRequest(
            path: "items/\(itemId.uuidString)/sharers",
            method: .put,
            body: request
        ))
    }
}

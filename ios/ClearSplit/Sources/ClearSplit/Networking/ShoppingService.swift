import Foundation

protocol ShoppingServicing {
    func listSessions(groupId: UUID) async throws -> [ShoppingSession]
    func getSession(sessionId: UUID) async throws -> ShoppingSession
    func createSession(groupId: UUID, request: ShoppingSessionCreate) async throws -> ShoppingSession
    func setParticipants(sessionId: UUID, request: ParticipantSetRequest) async throws -> ShoppingSession
    func uploadReceipt(sessionId: UUID, imageData: Data, contentType: String) async throws -> ReceiptUpload
    func getReceiptDownloadURL(receiptUploadId: UUID) async throws -> ReceiptDownloadURLResponse
    func deleteReceipt(receiptUploadId: UUID) async throws -> ReceiptDeleteResponse
    func extractReceiptItems(receiptUploadId: UUID) async throws -> [ReceiptExtractedItem]
    func getExtractedReceiptItems(receiptUploadId: UUID) async throws -> [ReceiptExtractedItem]
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
            method: "POST",
            body: request
        ))
    }
    
    func setParticipants(sessionId: UUID, request: ParticipantSetRequest) async throws -> ShoppingSession {
        try await client.request(APIRequest(
            path: "shopping-sessions/\(sessionId.uuidString)/participants",
            method: "PUT",
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
            method: "POST"
        )
        request.contentType = "multipart/form-data; boundary=\(boundary)"
        
        return try await client.upload(request: request, body: body)
    }
    
    func getReceiptDownloadURL(receiptUploadId: UUID) async throws -> ReceiptDownloadURLResponse {
        print("[ShoppingService] Requesting download URL for receipt: \(receiptUploadId)")
        let path = "receipts/\(receiptUploadId.uuidString)/download-url"
        print("[ShoppingService] Request path: \(path)")
        do {
            let response: ReceiptDownloadURLResponse = try await client.request(APIRequest(
                path: path
            ))
            print("[ShoppingService] ✅ Successfully received download URL response")
            return response
        } catch {
            print("[ShoppingService] ❌ Failed to get download URL: \(error)")
            throw error
        }
    }

    func deleteReceipt(receiptUploadId: UUID) async throws -> ReceiptDeleteResponse {
        print("[ShoppingService] Requesting delete for receipt: \(receiptUploadId)")
        let path = "receipts/\(receiptUploadId.uuidString)"
        return try await client.request(APIRequest(
            path: path,
            method: "DELETE"
        ))
    }
    
    func extractReceiptItems(receiptUploadId: UUID) async throws -> [ReceiptExtractedItem] {
        print("[ShoppingService] Triggering OCR extraction for receipt: \(receiptUploadId)")
        let path = "receipts/\(receiptUploadId.uuidString)/extract-items"
        do {
            let items: [ReceiptExtractedItem] = try await client.request(APIRequest(
                path: path,
                method: "POST"
            ))
            print("[ShoppingService] ✅ Successfully extracted \(items.count) items")
            return items
        } catch {
            if isCancellationError(error) {
                print("[ShoppingService] ℹ️ OCR extraction request was cancelled")
            } else {
                print("[ShoppingService] ❌ Failed to extract items: \(error)")
            }
            throw error
        }
    }
    
    func getExtractedReceiptItems(receiptUploadId: UUID) async throws -> [ReceiptExtractedItem] {
        print("[ShoppingService] Fetching extracted items for receipt: \(receiptUploadId)")
        let path = "receipts/\(receiptUploadId.uuidString)/extracted-items"
        do {
            let items: [ReceiptExtractedItem] = try await client.request(APIRequest(path: path))
            print("[ShoppingService] ✅ Successfully retrieved \(items.count) extracted items")
            return items
        } catch {
            if isCancellationError(error) {
                print("[ShoppingService] ℹ️ Extracted items request was cancelled")
            } else {
                print("[ShoppingService] ❌ Failed to get extracted items: \(error)")
            }
            throw error
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        if let apiError = error as? APIError,
           case .network(let underlyingError) = apiError {
            if underlyingError is CancellationError {
                return true
            }
            if let urlError = underlyingError as? URLError, urlError.code == .cancelled {
                return true
            }

            let nsError = underlyingError as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
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
            method: "PUT",
            body: request
        ))
    }
}

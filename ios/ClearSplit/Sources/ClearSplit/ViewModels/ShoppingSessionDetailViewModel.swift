import Foundation
import Combine
import UIKit

@MainActor
final class ShoppingSessionDetailViewModel: ObservableObject {
    @Published var session: ShoppingSession?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isUploadingReceipt = false
    @Published var uploadError: String?
    
    private let appState: AppState
    private let sessionId: UUID
    
    init(appState: AppState, sessionId: UUID) {
        self.appState = appState
        self.sessionId = sessionId
    }
    
    var totalCents: Int {
        session?.totalCents ?? 0
    }
    
    var formattedTotal: String {
        let dollars = Double(totalCents) / 100.0
        return String(format: "$%.2f", dollars)
    }
    
    var isPayer: Bool {
        // Check if current user is the payer
        // This would need membership context from app state
        true // Simplified for MVP
    }
    
    func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        
        do {
            session = try await appState.shoppingService.getSession(sessionId: sessionId)
        } catch {
            errorMessage = "Failed to load session details."
        }
    }
    
    func setParticipants(_ membershipIds: [UUID]) async -> Bool {
        guard let session = session else { return false }
        
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        
        do {
            let updated = try await appState.setParticipants(
                sessionId: session.id,
                groupId: session.groupId,
                membershipIds: membershipIds
            )
            self.session = updated
            return true
        } catch let APIError.server(_, message) {
            if let message, !message.isEmpty {
                errorMessage = message
            } else {
                errorMessage = "Failed to set participants."
            }
            return false
        } catch {
            errorMessage = "Failed to set participants."
            return false
        }
    }
    
    func uploadReceipt(imageData: Data, contentType: String = "image/jpeg") async -> Bool {
        guard let session = session else { return false }
        
        isUploadingReceipt = true
        defer { isUploadingReceipt = false }
        uploadError = nil
        
        do {
            _ = try await appState.shoppingService.uploadReceipt(
                sessionId: session.id,
                imageData: imageData,
                contentType: contentType
            )
            // Reload session to get updated receipts
            await load()
            return true
        } catch {
            uploadError = "Failed to upload receipt."
            return false
        }
    }
}

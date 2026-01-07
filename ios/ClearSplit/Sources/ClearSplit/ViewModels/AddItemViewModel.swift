import Foundation
import Combine

@MainActor
final class AddItemViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var quantity: String = "1"
    @Published var useUnitPrice: Bool = false
    @Published var unitPrice: String = ""
    @Published var totalPrice: String = ""
    @Published var isCreating = false
    @Published var errorMessage: String?
    
    @Published var selectedSharers: Set<UUID> = []
    @Published var isSettingSharers = false
    @Published var sharingError: String?
    
    private let appState: AppState
    private let sessionId: UUID
    private let participants: [ShoppingSessionParticipant]
    
    init(appState: AppState, sessionId: UUID, participants: [ShoppingSessionParticipant]) {
        self.appState = appState
        self.sessionId = sessionId
        self.participants = participants
    }
    
    var canCreateItem: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        
        if useUnitPrice {
            guard let _ = Double(unitPrice), let _ = Int(quantity) else { return false }
        } else {
            guard let _ = Double(totalPrice) else { return false }
        }
        
        return true
    }
    
    var canSetSharers: Bool {
        !selectedSharers.isEmpty
    }
    
    func createItem() async -> UUID? {
        guard canCreateItem else { return nil }
        
        isCreating = true
        defer { isCreating = false }
        errorMessage = nil
        
        do {
            let quantityInt = Int(quantity) ?? 1
            let request: ShoppingItemCreate
            
            if useUnitPrice, let unitPriceDollars = Double(unitPrice) {
                let unitPriceCents = Int(unitPriceDollars * 100)
                request = ShoppingItemCreate(
                    name: name.trimmingCharacters(in: .whitespaces),
                    quantity: quantityInt,
                    unitPriceCents: unitPriceCents,
                    totalCents: nil
                )
            } else if let totalDollars = Double(totalPrice) {
                let totalCents = Int(totalDollars * 100)
                request = ShoppingItemCreate(
                    name: name.trimmingCharacters(in: .whitespaces),
                    quantity: quantityInt,
                    unitPriceCents: nil,
                    totalCents: totalCents
                )
            } else {
                errorMessage = "Invalid price input."
                return nil
            }
            
            let item = try await appState.shoppingService.createItem(
                sessionId: sessionId,
                request: request
            )
            return item.id
        } catch {
            errorMessage = "Failed to create item."
            return nil
        }
    }
    
    func setSharers(itemId: UUID) async -> Bool {
        guard canSetSharers else { return false }
        
        isSettingSharers = true
        defer { isSettingSharers = false }
        sharingError = nil
        
        do {
            let request = SharersSetRequest(membershipIds: Array(selectedSharers))
            _ = try await appState.shoppingService.setSharers(itemId: itemId, request: request)
            return true
        } catch {
            sharingError = "Failed to set sharers."
            return false
        }
    }
    
    func toggleSharer(_ membershipId: UUID) {
        if selectedSharers.contains(membershipId) {
            selectedSharers.remove(membershipId)
        } else {
            selectedSharers.insert(membershipId)
        }
    }
    
    func selectAllSharers() {
        selectedSharers = Set(participants.map { $0.membershipId })
    }
}


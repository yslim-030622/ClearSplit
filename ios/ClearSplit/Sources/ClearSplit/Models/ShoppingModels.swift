import Foundation

// MARK: - Shopping Session

public struct ShoppingSession: Codable, Equatable, Identifiable {
    public let id: UUID
    public let groupId: UUID
    public let title: String
    public let shoppingDate: Date?
    public let currency: String
    public let paidByMembershipId: UUID
    public let createdAt: Date
    public let participants: [ShoppingSessionParticipant]
    public let receipts: [ReceiptUpload]
    public let items: [ShoppingItem]
    
    enum CodingKeys: String, CodingKey {
        case id, title, currency
        case groupId = "group_id"
        case shoppingDate = "shopping_date"
        case paidByMembershipId = "paid_by_membership_id"
        case createdAt = "created_at"
        case participants, receipts, items
    }
}

public struct ShoppingSessionCreate: Codable {
    public let title: String
    public let shoppingDate: Date?
    public let paidBy: UUID
    
    enum CodingKeys: String, CodingKey {
        case title
        case shoppingDate = "shopping_date"
        case paidBy = "paid_by"
    }
    
    public init(title: String, shoppingDate: Date?, paidBy: UUID) {
        self.title = title
        self.shoppingDate = shoppingDate
        self.paidBy = paidBy
    }
}

// MARK: - Participant

public struct ShoppingSessionParticipant: Codable, Equatable, Identifiable {
    public let id: UUID
    public let sessionId: UUID
    public let membershipId: UUID
    public let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case membershipId = "membership_id"
        case createdAt = "created_at"
    }
}

public struct ParticipantSetRequest: Codable {
    public let participantMembershipIds: [UUID]
    
    enum CodingKeys: String, CodingKey {
        case participantMembershipIds = "participant_membership_ids"
    }
    
    public init(participantMembershipIds: [UUID]) {
        self.participantMembershipIds = participantMembershipIds
    }
}

// MARK: - Receipt Upload

public struct ReceiptUpload: Codable, Equatable, Identifiable {
    public let id: UUID
    public let sessionId: UUID
    public let storageKey: String
    public let contentType: String
    public let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case storageKey = "storage_key"
        case contentType = "content_type"
        case createdAt = "created_at"
    }
}

// MARK: - Shopping Item

public struct ShoppingItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public let sessionId: UUID
    public let name: String
    public let quantity: Int
    public let unitPriceCents: Int?
    public let totalCents: Int
    public let createdAt: Date
    public let splits: [ShoppingItemSplit]
    
    enum CodingKeys: String, CodingKey {
        case id, name, quantity
        case sessionId = "session_id"
        case unitPriceCents = "unit_price_cents"
        case totalCents = "total_cents"
        case createdAt = "created_at"
        case splits
    }
}

public struct ShoppingItemCreate: Codable {
    public let name: String
    public let quantity: Int?
    public let unitPriceCents: Int?
    public let totalCents: Int?
    
    enum CodingKeys: String, CodingKey {
        case name, quantity
        case unitPriceCents = "unit_price_cents"
        case totalCents = "total_cents"
    }
    
    public init(name: String, quantity: Int? = nil, unitPriceCents: Int? = nil, totalCents: Int? = nil) {
        self.name = name
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.totalCents = totalCents
    }
}

// MARK: - Item Split

public struct ShoppingItemSplit: Codable, Equatable, Identifiable {
    public let id: UUID
    public let itemId: UUID
    public let membershipId: UUID
    public let shareCents: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case itemId = "item_id"
        case membershipId = "membership_id"
        case shareCents = "share_cents"
    }
}

public struct SharersSetRequest: Codable {
    public let membershipIds: [UUID]
    
    enum CodingKeys: String, CodingKey {
        case membershipIds = "membership_ids"
    }
    
    public init(membershipIds: [UUID]) {
        self.membershipIds = membershipIds
    }
}

public struct SharersSetResponse: Codable {
    public let itemId: UUID
    public let totalCents: Int
    public let splits: [ShoppingItemSplit]
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case totalCents = "total_cents"
        case splits
    }
}

// MARK: - Helper Extensions

extension ShoppingSession {
    /// Compute the total cost of all items in the session
    public var totalCents: Int {
        items.reduce(0) { $0 + $1.totalCents }
    }
    
    /// Check if a membership is a participant
    public func isParticipant(_ membershipId: UUID) -> Bool {
        participants.contains { $0.membershipId == membershipId }
    }
}

extension ShoppingItem {
    /// Formatted total price
    public var formattedTotal: String {
        let dollars = Double(totalCents) / 100.0
        return String(format: "$%.2f", dollars)
    }
    
    /// Formatted unit price
    public var formattedUnitPrice: String? {
        guard let unitPriceCents = unitPriceCents else { return nil }
        let dollars = Double(unitPriceCents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

extension ShoppingItemSplit {
    /// Formatted share amount
    public var formattedShare: String {
        let dollars = Double(shareCents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}


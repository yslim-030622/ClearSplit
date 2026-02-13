import Foundation

public enum ShoppingSessionStatus: String, Codable {
    case active
    case finalized
    case settled
}

// MARK: - Shopping Session

public struct ShoppingSession: Codable, Equatable, Identifiable {
    public let id: UUID
    public let groupId: UUID
    public let title: String
    public let shoppingDate: String?  // String format: "yyyy-MM-dd"
    public let totalAmount: Double?
    public let currency: String
    public let paidByMembershipId: UUID
    public let status: ShoppingSessionStatus
    public let finalizedAt: Date?
    public let settledAt: Date?
    public let createdAt: Date
    public let participants: [ShoppingSessionParticipant]
    public let receipts: [ReceiptUpload]
    public let items: [ShoppingItem]
}

public struct ShoppingSessionCreate: Codable {
    public let title: String
    public let shoppingDate: String?  // String format: "yyyy-MM-dd"
    public let totalAmount: Double?
    public let paidBy: UUID

    public init(title: String, shoppingDate: String?, totalAmount: Double? = nil, paidBy: UUID) {
        self.title = title
        self.shoppingDate = shoppingDate
        self.totalAmount = totalAmount
        self.paidBy = paidBy
    }
}

// MARK: - Participant

public struct ShoppingSessionParticipant: Codable, Equatable, Identifiable {
    public let id: UUID
    public let sessionId: UUID
    public let membershipId: UUID
    public let createdAt: Date
}

public struct ParticipantSetRequest: Codable {
    public let participantMembershipIds: [UUID]

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
}

public struct ReceiptDownloadURLResponse: Codable {
    public let receiptUploadId: UUID
    public let expiresInSeconds: Int
    public let url: String
}

public struct ReceiptDeleteResponse: Codable {
    public let receiptUploadId: UUID
    public let deleted: Bool
}

// MARK: - Receipt Extracted Item (OCR)

public struct ReceiptExtractedItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public let receiptUploadId: UUID
    public let name: String
    public let quantity: Int
    public let unitPriceCents: Int?
    public let totalCents: Int
    public let rawLine: String?
    public let confidence: Double?
    public let createdAt: Date
}

// MARK: - Shopping Item

public struct ShoppingItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public let sessionId: UUID
    public let name: String
    public let quantity: Int
    public let unitPriceCents: Int?
    public let totalCents: Int
    public let createdByMembershipId: UUID
    public let createdAt: Date
    public let splits: [ShoppingItemSplit]
}

public struct ShoppingItemCreate: Codable {
    public let name: String
    public let quantity: Int
    public let unitPriceCents: Int?
    public let totalCents: Int

    public init(name: String, quantity: Int, unitPriceCents: Int? = nil, totalCents: Int) {
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
}

public struct SharersSetRequest: Codable {
    public let membershipIds: [UUID]

    public init(membershipIds: [UUID]) {
        self.membershipIds = membershipIds
    }
}

public struct SharersSetResponse: Codable {
    public let itemId: UUID
    public let totalCents: Int
    public let splits: [ShoppingItemSplit]
}

// MARK: - Helper Extensions

extension ShoppingSession {
    /// Compute the total cost of all items in the session
    public var totalCents: Int {
        if let total = totalAmount {
            return Int(total * 100)
        }
        return items.reduce(0) { $0 + $1.totalCents }
    }

    /// Formatted total amount
    public var displayTotal: String {
        let dollars = Double(totalCents) / 100.0
        return String(format: "$%.2f", dollars)
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

    /// Formatted unit price derived from total and quantity
    public var formattedUnitPrice: String? {
        guard quantity > 0 else { return nil }
        let dollars = Double(totalCents) / Double(quantity) / 100.0
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

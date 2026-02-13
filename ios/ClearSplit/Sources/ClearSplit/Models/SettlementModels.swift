import Foundation

// MARK: - Settlement

public struct Settlement: Codable, Identifiable {
    public let id: UUID
    public let batchId: UUID
    public let fromMembership: UUID
    public let toMembership: UUID
    public let amountCents: Int
    public let status: String
    public let createdAt: Date
}

public extension Settlement {
    var displayAmount: String {
        let amountInDollars = Double(amountCents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD" // TODO: use group currency
        return formatter.string(from: NSNumber(value: amountInDollars)) ?? "$\(amountInDollars)"
    }
}

// MARK: - Settlement Batch

public struct SettlementBatch: Codable, Identifiable {
    public let id: UUID
    public let groupId: UUID
    public let status: String
    public let totalSettlements: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let version: Int
    public let voidedReason: String?
    public let settlements: [Settlement]?
}

// MARK: - Live Balances

public struct MembershipBalance: Codable, Identifiable {
    public let membershipId: UUID
    public let netCents: Int

    public var id: UUID { membershipId }
}

public struct SettlementSuggestion: Codable, Identifiable {
    public let fromMembership: UUID
    public let toMembership: UUID
    public let amountCents: Int

    public var id: String {
        "\(fromMembership.uuidString)-\(toMembership.uuidString)-\(amountCents)"
    }
}

public struct GroupBalances: Codable {
    public let groupId: UUID
    public let computedAt: Date
    public let balances: [MembershipBalance]
    public let suggestions: [SettlementSuggestion]
}

// MARK: - Settlement Payments

public struct SettlementPayment: Codable, Identifiable {
    public let id: UUID
    public let groupId: UUID
    public let fromMembership: UUID
    public let toMembership: UUID
    public let amountCents: Int
    public let status: String
    public let note: String?
    public let sentAt: Date?
    public let confirmedAt: Date?
    public let createdAt: Date
    public let sessionIds: [UUID]
}

public struct SettlementPaymentCreateRequest: Codable {
    public let fromMembership: UUID
    public let toMembership: UUID
    public let amountCents: Int
    public let note: String?
    public let sessionIds: [UUID]?
    public let autoConfirm: Bool

    public init(
        fromMembership: UUID,
        toMembership: UUID,
        amountCents: Int,
        note: String? = nil,
        sessionIds: [UUID]? = nil,
        autoConfirm: Bool
    ) {
        self.fromMembership = fromMembership
        self.toMembership = toMembership
        self.amountCents = amountCents
        self.note = note
        self.sessionIds = sessionIds
        self.autoConfirm = autoConfirm
    }
}

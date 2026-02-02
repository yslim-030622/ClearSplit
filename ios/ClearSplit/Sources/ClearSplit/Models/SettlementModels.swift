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

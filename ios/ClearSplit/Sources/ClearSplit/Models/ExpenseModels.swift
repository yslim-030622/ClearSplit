import Foundation

// MARK: - Expense

public struct Expense: Codable, Identifiable {
    public let id: UUID
    public let groupId: UUID
    public let title: String
    public let amountCents: Int
    public let currency: String
    public let paidBy: UUID
    public let paidByUser: User?
    public let expenseDate: String
    public let createdAt: Date
    public let updatedAt: Date?
}

public extension Expense {
    var displayAmount: String {
        let amountInDollars = Double(amountCents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amountInDollars)) ?? "\(currency) \(amountInDollars)"
    }
}

// MARK: - Create Expense Request

public struct CreateExpenseRequest: Codable {
    public let title: String
    public let amountCents: Int
    public let currency: String
    public let paidBy: UUID
    public let expenseDate: String  // ISO8601 date string
    public let splitAmong: [UUID]
}

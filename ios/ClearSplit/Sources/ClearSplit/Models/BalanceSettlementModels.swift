import Foundation

public enum BalanceStatus {
    case owed      // They get money back.
    case owes      // They owe money.
    case settled   // Already settled.
    case even      // Net balance is zero.
}

public struct IndividualBalance: Identifiable, Equatable {
    public let userId: UUID
    public let name: String
    public let balanceCents: Int // Positive = owed to them, Negative = they owe.
    public var isSettled: Bool

    public var id: UUID { userId }

    public var balance: Double {
        Double(balanceCents) / 100.0
    }

    public var balanceStatus: BalanceStatus {
        if isSettled {
            return .settled
        }
        if balanceCents > 1 {
            return .owed
        }
        if balanceCents < -1 {
            return .owes
        }
        return .even
    }

    public init(userId: UUID, name: String, balanceCents: Int, isSettled: Bool) {
        self.userId = userId
        self.name = name
        self.balanceCents = balanceCents
        self.isSettled = isSettled
    }
}

public struct SettlementPlan: Identifiable, Equatable {
    public let id: String
    public let fromUserId: UUID
    public let fromUserName: String
    public let toUserId: UUID
    public let toUserName: String
    public let amountCents: Int
    public var isSettled: Bool
    public var settledAt: Date?

    public var amount: Double {
        Double(amountCents) / 100.0
    }

    public var key: String {
        BalanceCalculator.paymentKey(
            fromUserId: fromUserId,
            toUserId: toUserId,
            amountCents: amountCents
        )
    }

    public var isCurrentUserInvolved: Bool {
        fromUserName == "You" || toUserName == "You"
    }

    public init(
        id: String,
        fromUserId: UUID,
        fromUserName: String,
        toUserId: UUID,
        toUserName: String,
        amountCents: Int,
        isSettled: Bool,
        settledAt: Date?
    ) {
        self.id = id
        self.fromUserId = fromUserId
        self.fromUserName = fromUserName
        self.toUserId = toUserId
        self.toUserName = toUserName
        self.amountCents = amountCents
        self.isSettled = isSettled
        self.settledAt = settledAt
    }
}

public enum BalanceCalculator {
    /// Calculate individual net balances from shopping sessions + confirmed payments.
    /// Positive result means others owe this member; negative means they owe.
    public static func calculateIndividualBalances(
        from sessions: [ShoppingSession],
        confirmedPayments: [SettlementPayment] = []
    ) -> [UUID: Int] {
        var balances: [UUID: Int] = [:]

        for session in sessions where session.status == .active || session.status == .finalized {
            let paidBy = session.paidByMembershipId

            for item in session.items {
                let totalItemCost = item.totalCents
                guard totalItemCost > 0 else { continue }

                balances[paidBy, default: 0] += totalItemCost

                if item.splits.isEmpty {
                    let sharedBy = session.participants.map(\.membershipId)
                    guard !sharedBy.isEmpty else { continue }

                    let costPerPerson = totalItemCost / sharedBy.count
                    var remainder = totalItemCost % sharedBy.count

                    for participantId in sharedBy {
                        let extra = remainder > 0 ? 1 : 0
                        balances[participantId, default: 0] -= costPerPerson + extra
                        remainder -= extra
                    }
                    continue
                }

                for split in item.splits {
                    balances[split.membershipId, default: 0] -= split.shareCents
                }
            }
        }

        for payment in confirmedPayments where payment.status.lowercased() == "confirmed" {
            balances[payment.fromMembership, default: 0] += payment.amountCents
            balances[payment.toMembership, default: 0] -= payment.amountCents
        }

        return balances
    }

    /// Round helper for UI display convenience.
    public static func roundToTwoDecimals(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    public static func paymentKey(fromUserId: UUID, toUserId: UUID, amountCents: Int) -> String {
        "\(fromUserId.uuidString)-\(toUserId.uuidString)-\(amountCents)"
    }
}

public enum SettlementOptimizer {
    /// Greedy optimization to minimize transfer count.
    public static func optimizeSettlements(
        balances: [UUID: Int],
        userNames: [UUID: String]
    ) -> [SettlementPlan] {
        var debtors = balances
            .filter { $0.value < -1 }
            .map { (userId: $0.key, amountCents: -$0.value) }
            .sorted {
                if $0.amountCents == $1.amountCents {
                    return $0.userId.uuidString < $1.userId.uuidString
                }
                return $0.amountCents > $1.amountCents
            }

        var creditors = balances
            .filter { $0.value > 1 }
            .map { (userId: $0.key, amountCents: $0.value) }
            .sorted {
                if $0.amountCents == $1.amountCents {
                    return $0.userId.uuidString < $1.userId.uuidString
                }
                return $0.amountCents > $1.amountCents
            }

        var settlements: [SettlementPlan] = []
        var sequence = 0

        while !debtors.isEmpty && !creditors.isEmpty {
            var debtor = debtors[0]
            var creditor = creditors[0]
            let paymentAmount = min(debtor.amountCents, creditor.amountCents)

            settlements.append(
                SettlementPlan(
                    id: "suggested-\(sequence)-\(paymentKey(from: debtor.userId, to: creditor.userId, amountCents: paymentAmount))",
                    fromUserId: debtor.userId,
                    fromUserName: userNames[debtor.userId] ?? "Unknown",
                    toUserId: creditor.userId,
                    toUserName: userNames[creditor.userId] ?? "Unknown",
                    amountCents: paymentAmount,
                    isSettled: false,
                    settledAt: nil
                )
            )
            sequence += 1

            debtor.amountCents -= paymentAmount
            creditor.amountCents -= paymentAmount

            if debtor.amountCents <= 1 {
                debtors.removeFirst()
            } else {
                debtors[0] = debtor
            }

            if creditor.amountCents <= 1 {
                creditors.removeFirst()
            } else {
                creditors[0] = creditor
            }
        }

        return settlements
    }

    private static func paymentKey(from: UUID, to: UUID, amountCents: Int) -> String {
        BalanceCalculator.paymentKey(fromUserId: from, toUserId: to, amountCents: amountCents)
    }
}

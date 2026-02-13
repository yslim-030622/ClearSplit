import XCTest
@testable import ClearSplit

final class ClearSplitTests: XCTestCase {
    func testHealthResponseDecoding() throws {
        let json = #"{"status":"ok"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(HealthResponse.self, from: data)
        XCTAssertEqual(decoded.status, "ok")
    }

    func testGroupBalancesDecoding() throws {
        let json = """
        {
          "group_id": "11111111-1111-1111-1111-111111111111",
          "computed_at": "2026-02-13T10:00:00Z",
          "balances": [
            {"membership_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "net_cents": 1500},
            {"membership_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "net_cents": -1500}
          ],
          "suggestions": [
            {
              "from_membership": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
              "to_membership": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
              "amount_cents": 1500
            }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GroupBalances.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.balances.count, 2)
        XCTAssertEqual(decoded.suggestions.first?.amountCents, 1500)
    }

    func testSettlementPaymentDecoding() throws {
        let json = """
        {
          "id": "99999999-9999-9999-9999-999999999999",
          "group_id": "11111111-1111-1111-1111-111111111111",
          "from_membership": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
          "to_membership": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "amount_cents": 500,
          "status": "pending",
          "note": "requested",
          "sent_at": "2026-02-13T10:00:00Z",
          "confirmed_at": null,
          "created_at": "2026-02-13T10:00:00Z",
          "session_ids": ["22222222-2222-2222-2222-222222222222"]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SettlementPayment.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.amountCents, 500)
        XCTAssertEqual(decoded.status, "pending")
        XCTAssertEqual(decoded.sessionIds.count, 1)
    }

    func testBalanceCalculatorComputesNetBalancesFromSplitsAndPayments() {
        let groupId = UUID()
        let sessionId = UUID()
        let payer = UUID()
        let memberA = UUID()
        let memberB = UUID()
        let now = Date(timeIntervalSince1970: 0)

        let itemId = UUID()
        let session = ShoppingSession(
            id: sessionId,
            groupId: groupId,
            title: "Weekly Grocery",
            shoppingDate: "2026-02-13",
            totalAmount: nil,
            currency: "USD",
            paidByMembershipId: payer,
            status: .finalized,
            finalizedAt: now,
            settledAt: nil,
            createdAt: now,
            participants: [
                ShoppingSessionParticipant(id: UUID(), sessionId: sessionId, membershipId: payer, createdAt: now),
                ShoppingSessionParticipant(id: UUID(), sessionId: sessionId, membershipId: memberA, createdAt: now),
                ShoppingSessionParticipant(id: UUID(), sessionId: sessionId, membershipId: memberB, createdAt: now)
            ],
            receipts: [],
            items: [
                ShoppingItem(
                    id: itemId,
                    sessionId: sessionId,
                    name: "Groceries",
                    quantity: 1,
                    unitPriceCents: nil,
                    totalCents: 3000,
                    createdByMembershipId: payer,
                    createdAt: now,
                    splits: [
                        ShoppingItemSplit(id: UUID(), itemId: itemId, membershipId: payer, shareCents: 1000),
                        ShoppingItemSplit(id: UUID(), itemId: itemId, membershipId: memberA, shareCents: 1000),
                        ShoppingItemSplit(id: UUID(), itemId: itemId, membershipId: memberB, shareCents: 1000)
                    ]
                )
            ]
        )

        let baseBalances = BalanceCalculator.calculateIndividualBalances(from: [session])
        XCTAssertEqual(baseBalances[payer], 2000)
        XCTAssertEqual(baseBalances[memberA], -1000)
        XCTAssertEqual(baseBalances[memberB], -1000)
        XCTAssertEqual(baseBalances.values.reduce(0, +), 0)

        let confirmedPayment = SettlementPayment(
            id: UUID(),
            groupId: groupId,
            fromMembership: memberA,
            toMembership: payer,
            amountCents: 1000,
            status: "confirmed",
            note: nil,
            sentAt: now,
            confirmedAt: now,
            createdAt: now,
            sessionIds: [sessionId]
        )

        let adjustedBalances = BalanceCalculator.calculateIndividualBalances(
            from: [session],
            confirmedPayments: [confirmedPayment]
        )
        XCTAssertEqual(adjustedBalances[payer], 1000)
        XCTAssertEqual(adjustedBalances[memberA], 0)
        XCTAssertEqual(adjustedBalances[memberB], -1000)
        XCTAssertEqual(adjustedBalances.values.reduce(0, +), 0)
    }

    func testSettlementOptimizerMinimizesTransfers() {
        let creditor = UUID()
        let debtorA = UUID()
        let debtorB = UUID()

        let settlements = SettlementOptimizer.optimizeSettlements(
            balances: [
                creditor: 2500,
                debtorA: -1000,
                debtorB: -1500
            ],
            userNames: [
                creditor: "You",
                debtorA: "Sarah",
                debtorB: "Mike"
            ]
        )

        XCTAssertEqual(settlements.count, 2)
        XCTAssertTrue(
            settlements.contains(where: {
                $0.fromUserId == debtorB &&
                $0.toUserId == creditor &&
                $0.amountCents == 1500
            })
        )
        XCTAssertTrue(
            settlements.contains(where: {
                $0.fromUserId == debtorA &&
                $0.toUserId == creditor &&
                $0.amountCents == 1000
            })
        )
        XCTAssertEqual(settlements.reduce(0) { $0 + $1.amountCents }, 2500)
    }
}

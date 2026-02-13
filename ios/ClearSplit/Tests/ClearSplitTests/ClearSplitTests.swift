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
}

import Foundation
import XCTest
@testable import ClearSplitCore

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("MockURLProtocol.requestHandler must be set before running the test")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class ClearSplitTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFormatCurrencyUsesTwoDecimalPlaces() {
        XCTAssertEqual(formatCurrency(cents: 1234, currency: "USD"), "$12.34")
        XCTAssertEqual(formatCurrency(cents: 0, currency: "USD"), "$0.00")
    }

    func testFormatDateStringReturnsOriginalWhenInvalid() {
        let invalid = "13-02-2026"
        XCTAssertEqual(formatDateString(invalid), invalid)
    }

    func testParseDateStringReturnsDateForValidInput() {
        XCTAssertNotNil(parseDateString("2026-02-13"))
    }

    func testParseDateStringReturnsNilForInvalidInput() {
        XCTAssertNil(parseDateString("not-a-date"))
        XCTAssertNil(parseDateString(nil))
    }

    func testUserDisplayNamePrefersFirstAndLastName() {
        let user = User(
            id: UUID(),
            username: "jane",
            email: "jane@example.com",
            firstName: "Jane",
            lastName: "Doe"
        )

        XCTAssertEqual(user.displayName, "Jane Doe")
        XCTAssertEqual(user.initials, "JD")
    }

    func testUserInitialsFallbackToUsernamePrefix() {
        let user = User(
            id: UUID(),
            username: "sammy",
            email: "sammy@example.com",
            firstName: "",
            lastName: ""
        )

        XCTAssertEqual(user.initials, "SA")
        XCTAssertEqual(user.displayName, "sammy")
    }

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

        let decoded = try makeDecoder().decode(GroupBalances.self, from: Data(json.utf8))
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

        let decoded = try makeDecoder().decode(SettlementPayment.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.amountCents, 500)
        XCTAssertEqual(decoded.status, "pending")
        XCTAssertEqual(decoded.sessionIds.count, 1)
    }

    func testShoppingSessionTotalCentsUsesItemsWhenTotalAmountMissing() throws {
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "group_id": "11111111-1111-1111-1111-111111111111",
          "title": "Groceries",
          "shopping_date": "2026-02-13",
          "total_amount": null,
          "currency": "USD",
          "paid_by_membership_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "status": "active",
          "finalized_at": null,
          "settled_at": null,
          "created_at": "2026-02-13T10:00:00Z",
          "participants": [],
          "receipts": [],
          "items": [
            {
              "id": "44444444-4444-4444-4444-444444444444",
              "session_id": "33333333-3333-3333-3333-333333333333",
              "name": "Milk",
              "quantity": 1,
              "unit_price_cents": 425,
              "total_cents": 425,
              "created_by_membership_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
              "created_at": "2026-02-13T10:00:00Z",
              "splits": []
            }
          ]
        }
        """

        let session = try makeDecoder().decode(ShoppingSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.totalCents, 425)
        XCTAssertEqual(session.displayTotal, "$4.25")
    }

    func testHealthClientFetchHealthUsesInjectedSession() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]

        let session = URLSession(configuration: config)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/health")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data(#"{"status":"ok"}"#.utf8)
            return (response, data)
        }

        let client = HealthClient(baseURL: URL(string: "https://example.com")!, session: session)
        let health = try await client.fetchHealth()

        XCTAssertEqual(health.status, "ok")
    }

    func testComputeGroupsInCommonCountsEachFriendAcrossGroups() {
        let now = Date(timeIntervalSince1970: 0)
        let currentUserId = UUID()
        let friendA = UUID()
        let friendB = UUID()
        let friendC = UUID()

        let group1 = Group(
            id: UUID(),
            name: "Trip",
            currency: "USD",
            createdAt: now,
            updatedAt: now,
            version: 1,
            userMembershipId: UUID()
        )
        let group2 = Group(
            id: UUID(),
            name: "House",
            currency: "USD",
            createdAt: now,
            updatedAt: now,
            version: 1,
            userMembershipId: UUID()
        )
        let group3 = Group(
            id: UUID(),
            name: "Project",
            currency: "USD",
            createdAt: now,
            updatedAt: now,
            version: 1,
            userMembershipId: UUID()
        )

        let membershipsByGroupId: [UUID: [Membership]] = [
            group1.id: [
                Membership(id: UUID(), groupId: group1.id, userId: currentUserId, role: "owner", createdAt: now, user: nil),
                Membership(id: UUID(), groupId: group1.id, userId: friendA, role: "member", createdAt: now, user: nil),
                Membership(id: UUID(), groupId: group1.id, userId: friendB, role: "member", createdAt: now, user: nil),
            ],
            group2.id: [
                Membership(id: UUID(), groupId: group2.id, userId: currentUserId, role: "owner", createdAt: now, user: nil),
                Membership(id: UUID(), groupId: group2.id, userId: friendA, role: "member", createdAt: now, user: nil),
            ],
            group3.id: [
                Membership(id: UUID(), groupId: group3.id, userId: currentUserId, role: "owner", createdAt: now, user: nil),
                Membership(id: UUID(), groupId: group3.id, userId: friendB, role: "member", createdAt: now, user: nil),
            ],
        ]

        let counts = FriendsViewModel.computeGroupsInCommon(
            friendUserIds: [friendA, friendB, friendC],
            groups: [group1, group2, group3],
            membershipsByGroupId: membershipsByGroupId
        )

        XCTAssertEqual(counts[friendA], 2)
        XCTAssertEqual(counts[friendB], 2)
        XCTAssertEqual(counts[friendC], 0)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

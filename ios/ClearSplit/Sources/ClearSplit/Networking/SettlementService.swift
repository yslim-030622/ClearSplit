import Foundation

protocol SettlementServicing {
    func getBalances(groupId: UUID) async throws -> GroupBalances
    func createPayment(groupId: UUID, request: SettlementPaymentCreateRequest) async throws -> SettlementPayment
    func confirmPayment(paymentId: UUID) async throws -> SettlementPayment
    func listPayments(groupId: UUID) async throws -> [SettlementPayment]
    func markSettlementPaid(settlementId: UUID) async throws -> Settlement
}

final class SettlementService: SettlementServicing {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func getBalances(groupId: UUID) async throws -> GroupBalances {
        try await client.request(
            APIRequest(path: "groups/\(groupId.uuidString)/balances")
        )
    }

    func createPayment(groupId: UUID, request: SettlementPaymentCreateRequest) async throws -> SettlementPayment {
        try await client.request(
            APIRequest(
                path: "groups/\(groupId.uuidString)/settlement-payments",
                method: "POST",
                body: request
            )
        )
    }

    func confirmPayment(paymentId: UUID) async throws -> SettlementPayment {
        try await client.request(
            APIRequest(
                path: "settlement-payments/\(paymentId.uuidString)/confirm",
                method: "POST"
            )
        )
    }

    func listPayments(groupId: UUID) async throws -> [SettlementPayment] {
        try await client.request(
            APIRequest(path: "groups/\(groupId.uuidString)/settlement-payments")
        )
    }

    func markSettlementPaid(settlementId: UUID) async throws -> Settlement {
        struct SettlementMarkPaidRequest: Codable {
            let status: String = "paid"
        }

        return try await client.request(
            APIRequest(
                path: "settlements/\(settlementId.uuidString)",
                method: "PATCH",
                body: SettlementMarkPaidRequest()
            )
        )
    }
}

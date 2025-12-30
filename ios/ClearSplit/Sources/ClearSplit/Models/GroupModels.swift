import Foundation

public struct CSGroup: Codable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let currency: String
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, currency
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

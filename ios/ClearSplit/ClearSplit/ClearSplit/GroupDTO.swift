//
//  GroupDTO.swift
//  ClearSplit
//
//  Data transfer object for Group (matches backend GroupRead schema)
//

import Foundation

struct GroupDTO: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let currency: String
    let createdAt: Date
    let updatedAt: Date
    let version: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, currency, version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CreateGroupRequest: Codable {
    let name: String
    let currency: String
}



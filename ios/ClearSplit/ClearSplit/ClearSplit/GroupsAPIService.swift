//
//  GroupsAPIService.swift
//  ClearSplit
//
//  API service for Groups operations
//

import Foundation

enum GroupsAPIService {
    /// List all groups for the current user
    static func listGroups() async throws -> [GroupDTO] {
        try await APIClient.shared.request("/groups", method: "GET", requiresAuth: true)
    }
    
    /// Create a new group
    static func createGroup(name: String, currency: String) async throws -> GroupDTO {
        let request = CreateGroupRequest(name: name, currency: currency)
        return try await APIClient.shared.request(
            "/groups",
            method: "POST",
            body: request,
            requiresAuth: true
        )
    }
}



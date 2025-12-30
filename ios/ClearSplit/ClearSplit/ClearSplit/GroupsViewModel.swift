//
//  GroupsViewModel.swift
//  ClearSplit
//

import Foundation
import Combine

@MainActor
final class GroupsViewModel: ObservableObject {
    @Published var groups: [GroupDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    
    func load() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedGroups = try await GroupsAPIService.listGroups()
            groups = fetchedGroups
            isLoading = false
            
            #if DEBUG
            print("✅ Loaded \(groups.count) groups")
            #endif
        } catch {
            isLoading = false
            handleError(error, context: "loading groups")
        }
    }
    
    func createGroup(name: String, currency: String) async throws {
        isLoading = true
        errorMessage = nil
        
        do {
            let newGroup = try await GroupsAPIService.createGroup(name: name, currency: currency)
            
            #if DEBUG
            print("✅ Created group: \(newGroup.name) (ID: \(newGroup.id))")
            print("   Currency: \(newGroup.currency)")
            print("   Current groups count: \(groups.count)")
            #endif
            
            // Add to local list immediately
            groups.append(newGroup)
            groups.sort { $0.createdAt > $1.createdAt } // Newest first
            
            #if DEBUG
            print("   Updated groups count: \(groups.count)")
            #endif
            
            isLoading = false
        } catch {
            isLoading = false
            #if DEBUG
            print("❌ Create group error: \(error)")
            if let apiError = error as? APIError {
                if case .decodingError(let decError) = apiError {
                    print("   Decoding detail: \(decError)")
                }
            }
            #endif
            handleError(error, context: "creating group")
            throw error // Re-throw so UI can handle dismissal
        }
    }
    
    private func handleError(_ error: Error, context: String) {
        #if DEBUG
        print("❌ Error \(context): \(error)")
        #endif
        
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                errorMessage = "Session expired. Please log in again."
            case .validationError(let message):
                errorMessage = message
            case .serverError(let code, let message):
                errorMessage = message ?? "Server error (\(code))"
            case .networkError:
                errorMessage = "Cannot connect to server. Check your connection."
            case .decodingError:
                errorMessage = "Failed to understand server response."
            default:
                errorMessage = "An error occurred: \(error.localizedDescription)"
            }
        } else {
            errorMessage = "An unexpected error occurred."
        }
        
        showError = true
    }
}

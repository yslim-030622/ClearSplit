//
//  AuthManager.swift
//  ClearSplit
//

import Foundation
import Combine

@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let tokens = KeychainService.getTokens() else {
            isAuthenticated = false
            return
        }
        
        do {
            _ = try await AuthService.me()
            isAuthenticated = true
        } catch {
            print("🚀 Bootstrap failed: \(error)")
            AuthService.logout()
            isAuthenticated = false
        }
    }
    
    func signUp(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let tokens = try await AuthService.signup(email: email, password: password)
            try KeychainService.saveTokens(tokens)
            isAuthenticated = true
            isLoading = false
        } catch {
            isLoading = false
            handleError(error, context: "signup")
        }
    }
    
    func logIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let tokens = try await AuthService.login(email: email, password: password)
            try KeychainService.saveTokens(tokens)
            isAuthenticated = true
            isLoading = false
        } catch {
            isLoading = false
            handleError(error, context: "login")
        }
    }
    
    func logOut() {
        AuthService.logout()
        isAuthenticated = false
        errorMessage = nil
    }
    
    private func handleError(_ error: Error, context: String) {
        print("🚀 [\(context.uppercased())] Error: \(error)")
        
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                errorMessage = "Invalid email or password."
            case .validationError(let message):
                errorMessage = message
            case .decodingError(let decError):
                errorMessage = "Internal Error: Failed to understand server response."
                print("❌ Decoding Detail: \(decError)")
            case .serverError(let code, let message):
                if code == 400 && context == "signup" {
                    errorMessage = "Email already registered."
                } else {
                    errorMessage = message ?? "Server error (\(code))."
                }
            case .networkError:
                errorMessage = connectionErrorMessage()
            default:
                errorMessage = "An unexpected error occurred."
            }
        } else {
            errorMessage = "Cannot connect to server. Please check your connection."
        }
    }
    
    private func connectionErrorMessage() -> String {
        #if DEBUG
        if APIConfig.baseURL.host == "localhost" || APIConfig.baseURL.host == "127.0.0.1" {
            return "Cannot connect to server. Running on a real device? Use your Mac's LAN IP instead of localhost."
        }
        #endif
        return "Cannot connect to server. Please check your connection."
    }
}

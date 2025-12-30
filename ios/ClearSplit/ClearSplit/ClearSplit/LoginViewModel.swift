//
//  LoginViewModel.swift
//  ClearSplit
//

import Foundation
import Combine

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var alertMessage: String?
    @Published var showAlert = false

    var onLoginSuccess: (() -> Void)?

    func login() async {
        guard validate() else { return }
        isLoading = true
        alertMessage = nil
        do {
            try await AuthService.login(email: email, password: password)
            isLoading = false
            onLoginSuccess?()
        } catch {
            isLoading = false
            handle(error)
        }
    }

    private func validate() -> Bool {
        guard !email.isEmpty else { present("Email is required"); return false }
        guard !password.isEmpty else { present("Password is required"); return false }
        return true
    }

    private func handle(_ error: Error) {
        print("Login failed: \(error)")
        switch error {
        case APIError.unauthorized:
            present("Invalid email or password.")
        case APIError.networkError:
            present(connectionMessage())
        case APIError.serverError(_, let msg):
            present(msg ?? "Server error.")
        default:
            present("Cannot connect to server.")
        }
    }

    private func connectionMessage() -> String {
        if APIConfig.baseURL.host == "localhost" {
            return "Cannot connect to server. If using a real device, use your Mac LAN IP instead of localhost."
        }
        return "Cannot connect to server."
    }

    private func present(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}


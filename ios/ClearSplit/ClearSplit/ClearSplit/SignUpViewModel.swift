//
//  SignUpViewModel.swift
//  ClearSplit
//

import Foundation
import Combine

@MainActor
final class SignUpViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var isLoading = false
    @Published var alertMessage: String?
    @Published var showAlert = false

    var onSignupSuccess: (() -> Void)?

    func signup() async {
        guard validate() else { return }
        isLoading = true
        alertMessage = nil
        do {
            try await AuthService.signup(email: email, password: password)
            isLoading = false
            onSignupSuccess?()
        } catch {
            isLoading = false
            handle(error)
        }
    }

    private func validate() -> Bool {
        guard !email.isEmpty else { present("Email is required"); return false }
        guard password.count >= 8 else { present("Password must be at least 8 characters"); return false }
        guard password == confirmPassword else { present("Passwords do not match"); return false }
        return true
    }

    private func handle(_ error: Error) {
        print("Signup failed: \(error)")
        switch error {
        case APIError.unauthorized:
            present("Signup failed. Please check your information.")
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
            return "Backend not reachable. If using a real device, use your Mac LAN IP instead of localhost."
        }
        return "Cannot connect to server."
    }

    private func present(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}


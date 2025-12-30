import Foundation

@MainActor
final class SignUpViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var isLoading = false
    @Published var alertMessage: String?
    @Published var showAlert = false

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func signup() async {
        guard validate() else { return }
        isLoading = true
        do {
            let _ = try await appState.authService.signup(email: email, password: password)
            // Fetch user info after signup/login
            let user = try await appState.authService.me()
            appState.user = user
            isLoading = false
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
        print("🚨 Signup failed: \(error)")
        switch error {
        case APIError.unauthorized:
            present("Signup failed. Please check your information.")
        case APIError.network, URLError.notConnectedToInternet:
            present(connectionMessage())
        case APIError.server(_, let message):
            present(message ?? "Server error.")
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


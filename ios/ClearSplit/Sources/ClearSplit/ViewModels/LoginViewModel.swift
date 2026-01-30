import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading = false
    @Published var alertMessage: String?
    @Published var showAlert = false

    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func login() async {
        guard validate() else { return }
        isLoading = true
        do {
            let (_, user) = try await appState.authService.login(identifier: email, password: password)
            appState.user = user
            isLoading = false
        } catch {
            isLoading = false
            handle(error)
        }
    }

    private func validate() -> Bool {
        guard !email.isEmpty else {
            present("Email is required")
            return false
        }
        guard !password.isEmpty else {
            present("Password is required")
            return false
        }
        return true
    }

    private func handle(_ error: Error) {
        print("🚨 Login failed: \(error)")
        switch error {
        case APIError.unauthorized:
            present("Invalid email or password.")
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
            return "Cannot connect to server. If using a real device, use your Mac LAN IP instead of localhost."
        }
        return "Cannot connect to server."
    }

    private func present(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}

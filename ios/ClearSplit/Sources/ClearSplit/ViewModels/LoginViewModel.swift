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
            try await appState.login(identifier: email, password: password)
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
        print("🌐 API base URL: \(APIConfig.baseURL.absoluteString)")
        switch error {
        case APIError.unauthorized:
            present("Invalid email or password.")
        case APIError.decoding:
            present("Received an unexpected response from the server (response format mismatch).")
        case APIError.network(let underlying as URLError):
            present(connectionMessage(for: underlying))
        case APIError.network(let underlying):
            present("Network error: \(underlying.localizedDescription)")
        case let urlError as URLError:
            present(connectionMessage(for: urlError))
        case APIError.server(let status, let message):
            present("Server error (\(status)): \(message ?? "No message")")
        default:
            present("Login failed: \(String(describing: error))")
        }
    }

    private func connectionMessage(for urlError: URLError? = nil) -> String {
        let host = APIConfig.baseURL.host?.lowercased()
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return "Cannot connect to server. If using a real device, set API_BASE_URL to your Mac LAN IP (e.g. http://192.168.x.x:8000)."
        }

        guard let urlError else {
            return "Cannot connect to server."
        }

        switch urlError.code {
        case .notConnectedToInternet:
            return "No internet connection."
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .timedOut:
            return "Cannot reach server at \(APIConfig.baseURL.absoluteString)."
        default:
            return "Cannot connect to server."
        }
    }

    private func present(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}

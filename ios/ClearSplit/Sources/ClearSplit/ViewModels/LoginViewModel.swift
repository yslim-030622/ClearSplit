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
        let identifier = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validate(identifier: identifier) else { return }
        if APIConfig.requiresLANBaseURLForCurrentRuntime {
            present(APIConfig.deviceLoopbackHintMessage)
            return
        }
        isLoading = true
        do {
            try await appState.login(identifier: identifier, password: password)
            isLoading = false
        } catch {
            isLoading = false
            handle(error)
        }
    }

    private func validate(identifier: String) -> Bool {
        guard !identifier.isEmpty else {
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
            if status == 401 {
                present(
                    "Invalid email/username or password. If this is a fresh local backend database, create an account first."
                )
                return
            }
            present("Server error (\(status)): \(message ?? "No message")")
        default:
            present("Login failed: \(String(describing: error))")
        }
    }

    private func connectionMessage(for urlError: URLError? = nil) -> String {
        if APIConfig.requiresLANBaseURLForCurrentRuntime {
            return APIConfig.deviceLoopbackHintMessage
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

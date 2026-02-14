import Foundation

@MainActor
final class SignUpViewModel: ObservableObject {
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var username: String = ""
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

    func signup() async -> Bool {
        guard validate() else { return false }
        if APIConfig.requiresLANBaseURLForCurrentRuntime {
            present(APIConfig.deviceLoopbackHintMessage)
            return false
        }
        isLoading = true
        do {
            try await appState.signup(
                username: username,
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName
            )
            isLoading = false
            return true
        } catch {
            isLoading = false
            handle(error)
            return false
        }
    }

    private func validate() -> Bool {
        guard !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            present("First name is required")
            return false
        }
        guard !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            present("Last name is required")
            return false
        }
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            present("Username is required")
            return false
        }
        guard trimmedUsername.count >= 3 else {
            present("Username must be at least 3 characters")
            return false
        }
        let usernameRegex = "^[a-zA-Z0-9_-]+$"
        guard trimmedUsername.range(of: usernameRegex, options: .regularExpression) != nil else {
            present("Username can only include letters, numbers, _ and -")
            return false
        }
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
        case APIError.network(let underlying as URLError):
            present(connectionMessage(for: underlying))
        case APIError.network(let underlying):
            present("Network error: \(underlying.localizedDescription)")
        case let urlError as URLError:
            present(connectionMessage(for: urlError))
        case APIError.server(_, let message):
            present(message ?? "Server error.")
        default:
            present("Sign up failed: \(error.localizedDescription)")
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

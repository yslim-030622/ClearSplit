import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel: LoginViewModel
    @State private var showSignUp = false

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(appState: appState))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("ClearSplit")
                    .font(.largeTitle.weight(.semibold))

                Group {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)

                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
                .disabled(viewModel.isLoading)

                Button {
                    Task { await viewModel.login() }
                } label: {
                    HStack {
                        if viewModel.isLoading { ProgressView().tint(.white) }
                        Text("Log In").bold()
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isLoading)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)

                Button("Create account") { showSignUp = true }
                    .padding(.top, 4)
                    .disabled(viewModel.isLoading)

                NavigationLink("", isActive: $showSignUp) {
                    SignUpView(appState: viewModel.appState)
                }
                .hidden()
            }
            .padding()
            .navigationTitle("Login")
            .alert("Error", isPresented: $viewModel.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage ?? "Unknown error")
            }
        }
    }
}

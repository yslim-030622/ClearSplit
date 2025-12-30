import SwiftUI

struct SignUpView: View {
    @StateObject private var viewModel: SignUpViewModel
    @Environment(\.dismiss) private var dismiss

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: SignUpViewModel(appState: appState))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Account")
                .font(.title.weight(.semibold))

            Group {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)

                SecureField("Password (min 8 chars)", text: $viewModel.password)
                    .textContentType(.newPassword)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)

                SecureField("Confirm Password", text: $viewModel.confirmPassword)
                    .textContentType(.newPassword)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
            .disabled(viewModel.isLoading)

            Button {
                Task { await viewModel.signup() }
            } label: {
                HStack {
                    if viewModel.isLoading { ProgressView().tint(.white) }
                    Text("Sign Up").bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.isLoading ? Color.gray : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.isLoading)
        }
        .padding()
        .navigationTitle("Sign Up")
        .alert("Sign Up Failed", isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "Unknown error")
        }
    }
}


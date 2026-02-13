import SwiftUI

struct SignUpView: View {
    @StateObject private var viewModel: SignUpViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    enum Field {
        case firstName
        case lastName
        case username
        case email
        case password
        case confirmPassword
    }

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: SignUpViewModel(appState: appState))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.blue50, Color.gray50],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: 24)

                        VStack(spacing: 8) {
                            Text("Create Account")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(.gray900)
                            Text("Set up your ClearSplit profile")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.gray600)
                        }

                        Spacer()
                            .frame(height: 24)

                        VStack(spacing: 16) {
                            VStack(spacing: 12) {
                                inputField(
                                    title: "First Name",
                                    placeholder: "John",
                                    text: $viewModel.firstName,
                                    field: .firstName,
                                    accessibilityIdentifier: "signup.firstNameField",
                                    textContentType: .givenName,
                                    submitLabel: .next
                                ) {
                                    focusedField = .lastName
                                }

                                inputField(
                                    title: "Last Name",
                                    placeholder: "Doe",
                                    text: $viewModel.lastName,
                                    field: .lastName,
                                    accessibilityIdentifier: "signup.lastNameField",
                                    textContentType: .familyName,
                                    submitLabel: .next
                                ) {
                                    focusedField = .username
                                }

                                inputField(
                                    title: "Username",
                                    placeholder: "john_doe",
                                    text: $viewModel.username,
                                    field: .username,
                                    accessibilityIdentifier: "signup.usernameField",
                                    textContentType: .username,
                                    submitLabel: .next
                                ) {
                                    focusedField = .email
                                }

                                inputField(
                                    title: "Email",
                                    placeholder: "you@example.com",
                                    text: $viewModel.email,
                                    field: .email,
                                    accessibilityIdentifier: "signup.emailField",
                                    textContentType: .emailAddress,
                                    keyboardType: .emailAddress,
                                    autocapitalization: .never,
                                    submitLabel: .next
                                ) {
                                    focusedField = .password
                                }

                                secureInputField(
                                    title: "Password",
                                    placeholder: "Minimum 8 characters",
                                    text: $viewModel.password,
                                    field: .password,
                                    accessibilityIdentifier: "signup.passwordField",
                                    textContentType: .newPassword,
                                    submitLabel: .next
                                ) {
                                    focusedField = .confirmPassword
                                }

                                secureInputField(
                                    title: "Confirm Password",
                                    placeholder: "Re-enter password",
                                    text: $viewModel.confirmPassword,
                                    field: .confirmPassword,
                                    accessibilityIdentifier: "signup.confirmPasswordField",
                                    textContentType: .newPassword,
                                    submitLabel: .done
                                ) {
                                    Task { _ = await viewModel.signup() }
                                }
                            }

                            Button {
                                Task {
                                    let success = await viewModel.signup()
                                    if success {
                                        dismiss()
                                    }
                                }
                            } label: {
                                HStack {
                                    if viewModel.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text("Create Account")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    viewModel.isLoading ||
                                    viewModel.email.isEmpty ||
                                    viewModel.password.isEmpty ||
                                    viewModel.confirmPassword.isEmpty
                                        ? Color.blue600.opacity(0.75)
                                        : Color.blue600
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(
                                viewModel.isLoading ||
                                viewModel.email.isEmpty ||
                                viewModel.password.isEmpty ||
                                viewModel.confirmPassword.isEmpty
                            )
                            .buttonStyle(ScaleButtonStyle())
                            .accessibilityIdentifier("signup.submitButton")
                        }
                        .padding(24)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.gray200, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)

                        Spacer()
                            .frame(height: 20)

                        Button("Already have an account? Log In") {
                            dismiss()
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray700)
                        .disabled(viewModel.isLoading)
                        .padding(.bottom, 24)
                        .accessibilityIdentifier("signup.loginLinkButton")
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isLoading)
                }
            }
        }
        .alert("Sign Up Failed", isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "Unknown error")
        }
    }

    private func inputField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        accessibilityIdentifier: String,
        textContentType: UITextContentType? = nil,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .words,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray700)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)

                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        focusedField == field ? Color.blue500 : Color.gray300,
                        lineWidth: focusedField == field ? 2 : 1
                    )

                TextField(placeholder, text: text)
                    .textContentType(textContentType)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray900)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .focused($focusedField, equals: field)
                    .submitLabel(submitLabel)
                    .onSubmit(onSubmit)
                    .accessibilityIdentifier(accessibilityIdentifier)
            }
            .frame(height: 48)
        }
        .disabled(viewModel.isLoading)
    }

    private func secureInputField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        accessibilityIdentifier: String,
        textContentType: UITextContentType? = nil,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray700)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)

                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        focusedField == field ? Color.blue500 : Color.gray300,
                        lineWidth: focusedField == field ? 2 : 1
                    )

                SecureField(placeholder, text: text)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray900)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .focused($focusedField, equals: field)
                    .submitLabel(submitLabel)
                    .onSubmit(onSubmit)
                    .accessibilityIdentifier(accessibilityIdentifier)
            }
            .frame(height: 48)
        }
        .disabled(viewModel.isLoading)
    }
}

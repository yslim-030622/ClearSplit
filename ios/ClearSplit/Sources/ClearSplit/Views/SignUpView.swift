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
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: 16)

                        cancelButtonRow

                        Spacer()
                            .frame(height: 20)

                        headerSection

                        Spacer()
                        .frame(height: 24)

                        VStack(spacing: 20) {
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
                                HStack(spacing: 8) {
                                    if viewModel.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text("Create Account")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryActionButtonStyle(isEnabled: canSubmit))
                            .disabled(!canSubmit)
                            .accessibilityIdentifier("signup.submitButton")
                        }
                        .padding(24)
                        .cardStyle()

                        Spacer()
                            .frame(height: 24)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert("Sign Up Failed", isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "Unknown error")
        }
    }

    private var canSubmit: Bool {
        !viewModel.isLoading &&
        !viewModel.email.isEmpty &&
        !viewModel.password.isEmpty &&
        !viewModel.confirmPassword.isEmpty
    }

    private var cancelButtonRow: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .font(ClearSplitTheme.Typography.bodyStrong)
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.borderLight, lineWidth: 1)
            )
            .applyElevation(.low)
            .disabled(viewModel.isLoading)

            Spacer()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Create Account")
                .font(ClearSplitTheme.Typography.hero)
                .foregroundColor(.textPrimary)

            Text("Set up your ClearSplit profile")
                .font(ClearSplitTheme.Typography.body)
                .foregroundColor(.textSecondary)
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
        labeledInput(title: title, isFocused: focusedField == field) {
            TextField(placeholder, text: text)
                .textContentType(textContentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .accessibilityIdentifier(accessibilityIdentifier)
                .disabled(viewModel.isLoading)
        }
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
        labeledInput(title: title, isFocused: focusedField == field) {
            SecureField(placeholder, text: text)
                .textContentType(textContentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .accessibilityIdentifier(accessibilityIdentifier)
                .disabled(viewModel.isLoading)
        }
    }

    private func labeledInput<Content: View>(
        title: String,
        isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(ClearSplitTheme.Typography.subheadline.weight(.medium))
                .foregroundColor(.textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.cardBackground : Color.cardInset)

                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isFocused ? Color.brandPrimary : Color.borderLight,
                        lineWidth: isFocused ? 2 : 1
                    )

                if isFocused {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.brandPrimary.opacity(0.20), lineWidth: 3)
                        .padding(-3)
                }

                content()
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            .frame(height: 48)
        }
    }
}
